(** HTTP transport implementation for MCP *)

open Eio

type server_config = { port : int; host : string }
type client_config = { base_url : string }

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
  | Client { config; client; response_queue; _ } ->
      (* For client, send HTTP POST request *)
      let json = Jsonrpc.Packet.yojson_of_t packet in
      let yojson = json_to_yojson json in
      let body = Yojson.Safe.to_string yojson in
      let headers =
        Http.Header.of_list [ ("Content-Type", "application/json") ]
      in
      let uri = Uri.of_string config.base_url in

      (* Send request and handle response *)
      Fiber.fork ~sw:t.sw (fun () ->
          try
            let resp, body =
              Cohttp_eio.Client.post ~sw:t.sw client uri ~headers
                ~body:(Cohttp_eio.Body.of_string body)
            in
            let status = Http.Response.status resp in
            if status = `OK then
              (* Read response body *)
              let body_str =
                Eio.Buf_read.(parse_exn take_all) body ~max_size:max_int
              in
              if body_str <> "" then
                try
                  let yojson = Yojson.Safe.from_string body_str in
                  let json = yojson_to_json yojson in
                  let response_packet = Jsonrpc.Packet.t_of_yojson json in
                  Stream.add response_queue response_packet
                with exn ->
                  Printf.eprintf "Failed to parse response: %s\n"
                    (Printexc.to_string exn)
              else if status <> `No_content then
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

let create_client ~sw ~base_url env =
  let client = Cohttp_eio.Client.make ~https:None (Eio.Stdenv.net env) in
  {
    mode =
      Client
        { config = { base_url }; client; response_queue = Stream.create 100 };
    closed = false;
    sw;
  }
