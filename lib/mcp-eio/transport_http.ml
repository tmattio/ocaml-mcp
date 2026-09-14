(** HTTP transport implementation for MCP *)

open Eio

type server_config = { port : int; host : string }
type client_config = { base_url : string; headers : (string * string) list }

type mode =
  | Server of {
      config : server_config;
      (* Queue of incoming requests *)
      request_queue : Jsonrpc.Packet.t Stream.t;
      (* Table mapping request to response promise *)
      response_table : (Jsonrpc.Packet.t, Jsonrpc.Packet.t Promise.u) Hashtbl.t;
    }
  | Client of {
      config : client_config;
      client : Cohttp_eio.Client.t;
      (* Queue for received packets *)
      response_queue : Jsonrpc.Packet.t Stream.t;
      (* Session id assigned by a Streamable HTTP server, echoed on
         subsequent requests *)
      mutable session_id : string option;
      (* Protocol version negotiated during initialize, echoed on
         subsequent requests *)
      mutable protocol_version : string option;
    }

type t = { mode : mode; mutable closed : bool; sw : Switch.t }

(* Convert between jsonrpc and yojson - reuse from framing *)
let json_to_yojson = Framing.json_to_yojson
let yojson_to_json = Framing.yojson_to_json

let create_server ~sw ~port ?(host = "127.0.0.1") () =
  {
    mode =
      Server
        {
          config = { port; host };
          request_queue = Stream.create 100;
          response_table = Hashtbl.create 16;
        };
    closed = false;
    sw;
  }

(* The Streamable HTTP spec requires clients to echo the protocol version
   negotiated during initialize, so sniff it from the initialize result. *)
let note_protocol_version set_version (packet : Jsonrpc.Packet.t) =
  match packet with
  | Jsonrpc.Packet.Response { result = Ok json; _ } -> (
      match json_to_yojson json with
      | `Assoc fields -> (
          match List.assoc_opt "protocolVersion" fields with
          | Some (`String v) -> set_version v
          | _ -> ())
      | _ -> ())
  | _ -> ()

let queue_packet ~set_version response_queue body_str =
  try
    let yojson = Yojson.Safe.from_string body_str in
    let json = yojson_to_json yojson in
    let packet = Jsonrpc.Packet.t_of_yojson json in
    note_protocol_version set_version packet;
    Stream.add response_queue packet
  with exn ->
    Printf.eprintf "Failed to parse response: %s\n" (Printexc.to_string exn)

(* Read a text/event-stream body incrementally, queueing each event's data
   as a JSON-RPC packet. A single POST can yield several messages (e.g.
   progress notifications followed by the final response). *)
let consume_sse_body ~set_version response_queue reader =
  let sse = Sse.create () in
  let dispatch = function
    | Some { Sse.data; _ } -> queue_packet ~set_version response_queue data
    | None -> ()
  in
  let rec loop () =
    match Buf_read.line reader with
    | line ->
        dispatch (Sse.feed_line sse line);
        loop ()
    | exception End_of_file -> dispatch (Sse.feed_line sse "")
  in
  loop ()

let send t packet =
  if t.closed then failwith "Transport is closed";
  match t.mode with
  | Server { response_table; _ } ->
      (* Find the corresponding request and resolve its promise *)
      let found = ref false in
      Hashtbl.iter
        (fun req_packet resolver ->
          if not !found then
            match req_packet with
            | Jsonrpc.Packet.Request req -> (
                (* Match response to request by ID *)
                match packet with
                | Jsonrpc.Packet.Response resp when resp.id = req.id ->
                    Promise.resolve resolver packet;
                    Hashtbl.remove response_table req_packet;
                    found := true
                | _ -> ())
            | _ -> ())
        response_table;

      if not !found then
        (* If no matching request, it might be a notification or request from server *)
        ()
  | Client ({ config; client; response_queue; _ } as c) ->
      (* For client, send HTTP POST request *)
      let json = Jsonrpc.Packet.yojson_of_t packet in
      let yojson = json_to_yojson json in
      let body = Yojson.Safe.to_string yojson in
      let headers =
        Http.Header.of_list
          ([
             ("Content-Type", "application/json");
             ("Accept", "application/json, text/event-stream");
           ]
          @ config.headers
          @ (match c.session_id with
            | Some sid -> [ ("Mcp-Session-Id", sid) ]
            | None -> [])
          @
          match c.protocol_version with
          | Some v -> [ ("MCP-Protocol-Version", v) ]
          | None -> [])
      in
      let uri = Uri.of_string config.base_url in
      let set_version v = c.protocol_version <- Some v in

      (* Send request and handle response *)
      Fiber.fork ~sw:t.sw (fun () ->
          try
            let resp, body =
              Cohttp_eio.Client.post ~sw:t.sw client uri ~headers
                ~body:(Cohttp_eio.Body.of_string body)
            in
            let resp_headers = Http.Response.headers resp in
            (match Http.Header.get resp_headers "mcp-session-id" with
            | Some sid -> c.session_id <- Some sid
            | None -> ());
            let status = Http.Response.status resp in
            let code = Http.Status.to_int status in
            if code >= 200 && code < 300 then (
              if code <> 202 && code <> 204 then
                let content_type =
                  Option.value ~default:""
                    (Http.Header.get resp_headers "content-type")
                  |> String.lowercase_ascii
                in
                let is_event_stream =
                  String.length content_type >= 17
                  && String.sub content_type 0 17 = "text/event-stream"
                in
                if is_event_stream then
                  let reader = Buf_read.of_flow body ~max_size:max_int in
                  consume_sse_body ~set_version response_queue reader
                else
                  let body_str =
                    Eio.Buf_read.(parse_exn take_all) body ~max_size:max_int
                  in
                  if body_str <> "" then
                    queue_packet ~set_version response_queue body_str)
            else
              Printf.eprintf "HTTP request failed with status: %s\n"
                (Cohttp.Code.string_of_status status)
          with exn ->
            Printf.eprintf "HTTP request error: %s\n" (Printexc.to_string exn))

let recv t ~clock ?timeout () =
  if t.closed then None
  else
    match timeout with
    | None -> (
        match t.mode with
        | Server { request_queue; _ } ->
            (* Take from the request queue *)
            Stream.take_nonblocking request_queue
        | Client { response_queue; _ } ->
            (* Take from the response queue *)
            Stream.take_nonblocking response_queue)
    | Some duration -> (
        match t.mode with
        | Server { request_queue; _ } ->
            (* Take from the request queue with timeout *)
            Eio.Time.with_timeout_exn clock duration (fun () ->
                Some (Stream.take request_queue))
        | Client { response_queue; _ } ->
            (* Take from the response queue with timeout *)
            Eio.Time.with_timeout_exn clock duration (fun () ->
                Some (Stream.take response_queue)))

let close t = t.closed <- true

(* HTTP server handler for MCP *)
let make_handler (mode : mode) =
  match mode with
  | Server { request_queue; response_table; _ } -> (
      fun _conn (request : Http.Request.t) body ->
        match request.meth with
        | `POST -> (
            let body_str =
              Eio.Buf_read.(parse_exn take_all) body ~max_size:max_int
            in
            if body_str = "" then
              Cohttp_eio.Server.respond ~status:`No_content
                ~body:(Cohttp_eio.Body.of_string "")
                ()
            else
              try
                let yojson = Yojson.Safe.from_string body_str in
                let json = yojson_to_json yojson in
                let packet = Jsonrpc.Packet.t_of_yojson json in

                (* Create promise for response *)
                let response_promise, response_resolver = Promise.create () in
                Hashtbl.add response_table packet response_resolver;

                (* Add to request queue *)
                Stream.add request_queue packet;

                (* Wait for response *)
                let response_packet = Promise.await response_promise in
                let response_json =
                  Jsonrpc.Packet.yojson_of_t response_packet
                in
                let response_yojson = json_to_yojson response_json in
                let response_str = Yojson.Safe.to_string response_yojson in

                let headers =
                  Http.Header.of_list [ ("Content-Type", "application/json") ]
                in
                Cohttp_eio.Server.respond ~status:`OK ~headers
                  ~body:(Cohttp_eio.Body.of_string response_str)
                  ()
              with exn ->
                let error_msg =
                  Printf.sprintf "Error processing request: %s"
                    (Printexc.to_string exn)
                in
                Cohttp_eio.Server.respond ~status:`Bad_request
                  ~body:(Cohttp_eio.Body.of_string error_msg)
                  ())
        | _ ->
            Cohttp_eio.Server.respond ~status:`Method_not_allowed
              ~body:(Cohttp_eio.Body.of_string "Only POST is supported")
              ())
  | Client _ -> failwith "make_handler called on client transport"

(* Run HTTP server *)
let run_server t env =
  match t.mode with
  | Server { config; _ } ->
      let net = Eio.Stdenv.net env in
      let addr =
        `Tcp
          ( (if config.host = "127.0.0.1" then Eio.Net.Ipaddr.V4.loopback
             else Eio.Net.Ipaddr.V4.any),
            config.port )
      in
      let server_spec =
        Cohttp_eio.Server.make ~callback:(make_handler t.mode) ()
      in
      let server_socket =
        Eio.Net.listen net ~sw:t.sw ~backlog:128 ~reuse_addr:true addr
      in
      Cohttp_eio.Server.run server_socket server_spec ~on_error:(fun ex ->
          Logs.warn (fun f -> f "HTTP server error: %a" Eio.Exn.pp ex))
  | Client _ -> failwith "Cannot run server on client transport"

let create_client ~sw ~base_url ?(headers = []) ?https env =
  let client = Cohttp_eio.Client.make ~https (Eio.Stdenv.net env) in
  {
    mode =
      Client
        {
          config = { base_url; headers };
          client;
          response_queue = Stream.create 100;
          session_id = None;
          protocol_version = None;
        };
    closed = false;
    sw;
  }
