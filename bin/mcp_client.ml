(** MCP Client CLI *)

open Eio_main
open Mcp.Types
open Eio

type config = { name : string; version : string }
(** High-level client configuration *)

let default_config = { name = "mcp-client"; version = "0.1.0" }

type notification_handler = {
  on_resources_list_changed : unit -> unit; [@warning "-69"]
  on_resources_updated : string -> unit; [@warning "-69"]
  on_tools_list_changed : unit -> unit; [@warning "-69"]
  on_prompts_list_changed : unit -> unit; [@warning "-69"]
  on_roots_list_changed : unit -> unit; [@warning "-69"]
  on_logging_message : Mcp.Notification.Message.params -> unit; [@warning "-69"]
  on_sampling_message : Mcp.Types.SamplingMessage.t -> unit; [@warning "-69"]
}

type client = {
  client : Mcp.Client.t;
  connection : Mcp_eio.Connection.t;
  mutable server_info : ServerInfo.t option;
  mutable capabilities : Capabilities.server option;
  mutable notification_handler : notification_handler option; [@warning "-69"]
  sw : Switch.t; [@warning "-69"]
  (* Pending requests waiting for responses *)
  pending :
    ( Jsonrpc.Id.t,
      (Yojson.Safe.t, Jsonrpc.Response.Error.t) result Promise.u )
    Hashtbl.t;
      [@warning "-69"]
}

let connect ~sw ~connection ~config =
  let handler : Mcp.Client.notification_handler =
    {
      on_resources_updated = (fun _ -> ());
      on_resources_list_changed = (fun _ -> ());
      on_prompts_list_changed = (fun _ -> ());
      on_tools_list_changed = (fun _ -> ());
      on_message = (fun _ -> ());
    }
  in

  let client_info =
    { Mcp.Types.ClientInfo.name = config.name; version = config.version }
  in
  let client_capabilities =
    {
      Mcp.Types.Capabilities.experimental = None;
      sampling = None;
      elicitation = None;
      roots = None;
    }
  in

  let client =
    Mcp.Client.create ~notification_handler:handler ~client_info
      ~client_capabilities ()
  in

  let t =
    {
      client;
      connection;
      server_info = None;
      capabilities = None;
      notification_handler = None;
      sw;
      pending = Hashtbl.create 16;
    }
  in

  (* Send initialize request *)
  let init_promise, init_resolver = Promise.create () in
  let init_callback result = Promise.resolve init_resolver result in
  Mcp_eio.Connection.send_request connection client
    (Initialize
       {
         protocol_version = "2025-06-18";
         capabilities = client_capabilities;
         client_info;
       })
    init_callback;

  (* Process messages until initialized *)
  let rec wait_for_init () =
    match Mcp_eio.Connection.recv connection with
    | None -> failwith "Connection closed during initialization"
    | Some msg ->
        (match Mcp.Client.handle_message client msg with
        | Some response -> Mcp_eio.Connection.send connection response
        | None -> ());
        if not (Promise.is_resolved init_promise) then wait_for_init ()
  in
  wait_for_init ();

  (* Get initialization result *)
  match Promise.await init_promise with
  | Ok json -> (
      match Mcp.Request.Initialize.result_of_yojson json with
      | Ok result ->
          t.server_info <- Some result.server_info;
          t.capabilities <- Some result.capabilities;
          (* Don't start background handler for CLI - we just make requests and exit *)
          t
      | Error msg ->
          failwith (Printf.sprintf "Failed to parse initialize result: %s" msg))
  | Error _err -> failwith (Printf.sprintf "Initialize failed: JSON-RPC error")

let server_info t =
  match t.server_info with
  | Some info -> info
  | None -> failwith "Not initialized"

let capabilities t =
  match t.capabilities with
  | Some caps -> caps
  | None -> failwith "Not initialized"

(* Helper to make synchronous requests *)
let request t req =
  let promise, resolver = Promise.create () in
  let callback result = Promise.resolve resolver result in
  Mcp_eio.Connection.send_request t.connection t.client req callback;

  (* Process messages until we get our response *)
  let rec wait_for_response () =
    if Promise.is_resolved promise then ()
    else
      match Mcp_eio.Connection.recv t.connection with
      | None -> failwith "Connection closed while waiting for response"
      | Some msg ->
          (match Mcp.Client.handle_message t.client msg with
          | Some response -> Mcp_eio.Connection.send t.connection response
          | None -> ());
          wait_for_response ()
  in
  wait_for_response ();

  match Promise.await promise with
  | Ok json -> json
  | Error _err -> failwith "Request failed: JSON-RPC error"

let list_resources t ?cursor ?meta () =
  let json = request t (ResourcesList { cursor; meta }) in
  match Mcp.Request.Resources.List.result_of_yojson json with
  | Ok result -> result
  | Error msg ->
      failwith (Printf.sprintf "Failed to parse resources list: %s" msg)

let read_resource t ~uri ?meta () =
  let json = request t (ResourcesRead { uri; meta }) in
  match Mcp.Request.Resources.Read.result_of_yojson json with
  | Ok result -> result
  | Error msg ->
      failwith (Printf.sprintf "Failed to parse resource read: %s" msg)

let subscribe_resource t ~uri =
  let _json = request t (ResourcesSubscribe { uri; meta = None }) in
  ()

let unsubscribe_resource t ~uri =
  let _json = request t (ResourcesUnsubscribe { uri; meta = None }) in
  ()

let _ = (subscribe_resource, unsubscribe_resource)

let list_tools t ?cursor ?meta () =
  let json = request t (ToolsList { cursor; meta }) in
  match Mcp.Request.Tools.List.result_of_yojson json with
  | Ok result -> result
  | Error msg -> failwith (Printf.sprintf "Failed to parse tools list: %s" msg)

let call_tool t ~name ?arguments ?meta () =
  let json = request t (ToolsCall { name; arguments; meta }) in
  match Mcp.Request.Tools.Call.result_of_yojson json with
  | Ok result -> result
  | Error msg ->
      failwith (Printf.sprintf "Failed to parse tool call result: %s" msg)

let list_prompts t ?cursor ?meta () =
  let json = request t (PromptsList { cursor; meta }) in
  match Mcp.Request.Prompts.List.result_of_yojson json with
  | Ok result -> result
  | Error msg ->
      failwith (Printf.sprintf "Failed to parse prompts list: %s" msg)

let get_prompt t ~name ?arguments () =
  let arguments =
    Option.map
      (fun args ->
        match args with
        | `Assoc kvs ->
            List.map
              (fun (k, v) ->
                match v with
                | `String value -> (k, value)
                | _ -> failwith "Prompt arguments must be strings")
              kvs
        | _ -> failwith "Prompt arguments must be an object")
      arguments
  in
  let json = request t (PromptsGet { name; arguments; meta = None }) in
  match Mcp.Request.Prompts.Get.result_of_yojson json with
  | Ok result -> result
  | Error msg ->
      failwith (Printf.sprintf "Failed to parse prompt get result: %s" msg)

let _ = get_prompt

let set_log_level t ~level =
  let _json = request t (LoggingSetLevel { level; meta = None }) in
  ()

let set_notification_handler t handler = t.notification_handler <- Some handler

let close t =
  (* TODO: Send close notification if needed *)
  Mcp_eio.Connection.close t.connection

let _ = (set_log_level, set_notification_handler, close)

(** Transport configuration *)
type transport_config = Stdio | Socket of int | Pipe of string

let connect_transport ~env ~sw config =
  match config with
  | Stdio ->
      (* Use stdin/stdout of the current process *)
      let stdin = Eio.Stdenv.stdin env in
      let stdout = Eio.Stdenv.stdout env in
      let transport = Mcp_eio.Stdio.create ~stdin ~stdout in
      Mcp_eio.Connection.create (module Mcp_eio.Stdio) transport
  | Socket port ->
      (* Connect to TCP socket *)
      let net = Eio.Stdenv.net env in
      let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
      let transport = Mcp_eio.Socket.create_client ~net ~sw addr in
      Mcp_eio.Connection.create (module Mcp_eio.Socket) transport
  | Pipe path ->
      (* Connect to Unix domain socket *)
      let net = Eio.Stdenv.net env in
      let addr = `Unix path in
      let transport = Mcp_eio.Socket.create_client ~net ~sw addr in
      Mcp_eio.Connection.create (module Mcp_eio.Socket) transport

let with_client ~transport_config f =
  run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  (* Create connection based on configuration *)
  let connection = connect_transport ~env ~sw transport_config in

  (* Connect client *)
  let client = connect ~sw ~connection ~config:default_config in

  (* Run the function and ensure cleanup *)
  Fun.protect ~finally:(fun () -> close client) (fun () -> f client)

let format_content content =
  match content with
  | Mcp.Types.Content.Text { text; _ } -> text
  | Mcp.Types.Content.EmbeddedResource { resource; _ } ->
      Printf.sprintf "[Resource: %s]\n%s" resource.uri
        (Option.value resource.text ~default:"(binary content)")
  | Mcp.Types.Content.Image _ -> "[Image content]"
  | Mcp.Types.Content.Audio _ -> "[Audio content]"
  | Mcp.Types.Content.ResourceLink { uri; title; _ } ->
      Printf.sprintf "[Link: %s]%s" uri
        (Option.fold ~none:"" ~some:(Printf.sprintf " %s") title)

(* Use stderr for output when using stdio transport *)
let output_channel = ref stdout
let use_stderr () = output_channel := stderr
let printf fmt = Printf.fprintf !output_channel fmt
let eprintf fmt = Printf.eprintf fmt

(* Simple CLI argument parsing *)

let print_usage () =
  eprintf "MCP Client - interact with MCP servers\n\n";
  eprintf "Usage: mcp-client [OPTIONS] COMMAND [ARGS]\n\n";
  eprintf "Commands:\n";
  eprintf "  list <what>         List resources, tools, or prompts\n";
  eprintf "  call <tool> [args]  Call a tool\n";
  eprintf "  read <uri>          Read a resource\n";
  eprintf "  info                Show server information\n\n";
  eprintf "Options:\n";
  eprintf "  --socket <port>     Connect to TCP port\n";
  eprintf "  --pipe <path>       Connect to Unix socket\n";
  eprintf "  --stdio             Use stdin/stdout (default)\n";
  eprintf "  -a, --args <json>   Tool arguments as JSON\n";
  eprintf "  -m, --meta <json>   Metadata as JSON\n";
  exit 1

let parse_transport args =
  let rec parse_opts opts transport meta =
    match opts with
    | [] -> (transport, meta, [])
    | "--socket" :: port :: rest ->
        parse_opts rest (Socket (int_of_string port)) meta
    | "--pipe" :: path :: rest -> parse_opts rest (Pipe path) meta
    | "--stdio" :: rest -> parse_opts rest Stdio meta
    | ("-m" | "--meta") :: json :: rest -> parse_opts rest transport (Some json)
    | other -> (transport, meta, other)
  in
  parse_opts args Stdio None

let list_cmd transport_config what meta =
  with_client ~transport_config (fun client ->
      match String.lowercase_ascii what with
      | "resources" ->
          let result = list_resources client ?meta () in
          printf "Resources (%d):\n" (List.length result.resources);
          List.iter
            (fun r ->
              printf "- %s: %s\n" r.Mcp.Types.Resource.uri
                (Option.value r.Mcp.Types.Resource.description
                   ~default:r.Mcp.Types.Resource.name))
            result.resources
      | "tools" ->
          let result = list_tools client ?meta () in
          printf "Tools (%d):\n" (List.length result.tools);
          List.iter
            (fun t ->
              printf "- %s: %s\n" t.Mcp.Types.Tool.name
                (Option.value t.Mcp.Types.Tool.description
                   ~default:"No description"))
            result.tools
      | "prompts" ->
          let result = list_prompts client ?meta () in
          printf "Prompts (%d):\n" (List.length result.prompts);
          List.iter
            (fun p ->
              printf "- %s: %s\n" p.Mcp.Types.Prompt.name
                (Option.value p.Mcp.Types.Prompt.description
                   ~default:"No description"))
            result.prompts
      | _ ->
          eprintf "Unknown list target: %s\n" what;
          exit 1)

let call_cmd transport_config tool_name args_json meta =
  with_client ~transport_config (fun client ->
      let arguments =
        Option.map
          (fun json_str ->
            try Yojson.Safe.from_string json_str
            with Yojson.Json_error msg ->
              eprintf "Invalid JSON: %s\n" msg;
              exit 1)
          args_json
      in

      let result = call_tool client ~name:tool_name ?arguments ?meta () in

      List.iter
        (fun content -> printf "%s\n" (format_content content))
        result.content)

let read_cmd transport_config uri meta =
  with_client ~transport_config (fun client ->
      let result = read_resource client ~uri ?meta () in
      printf "Resource contents:\n";
      List.iter
        (fun content ->
          printf "[%s] %s\n" content.Mcp.Types.Content.uri
            (Option.value content.text ~default:"(binary content)"))
        result.contents)

let info_cmd transport_config =
  with_client ~transport_config (fun client ->
      let info = server_info client in
      let caps = capabilities client in

      printf "Server: %s v%s\n" info.name info.version;
      printf "\nCapabilities:\n";

      if caps.tools <> None then printf "- Tools\n";
      if caps.resources <> None then printf "- Resources\n";
      if caps.prompts <> None then printf "- Prompts\n";
      if caps.logging <> None then printf "- Logging\n";
      if caps.completions <> None then printf "- Completions\n";
      if caps.experimental <> None then printf "- Experimental\n")

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let transport, meta_json, remaining_args = parse_transport args in
  let meta =
    match meta_json with
    | None -> None
    | Some json_str -> (
        match Yojson.Safe.from_string json_str with
        | exception Yojson.Json_error msg ->
            eprintf "Invalid meta JSON: %s\n" msg;
            exit 1
        | json -> (
            (* Validate the meta JSON *)
            match Mcp.Meta.validate (Some json) with
            | Ok () -> Some json
            | Error msg ->
                eprintf "Invalid meta JSON: %s\n" msg;
                exit 1))
  in

  (* Use stderr for output when using stdio transport *)
  (match transport with Stdio -> use_stderr () | _ -> ());

  match remaining_args with
  | "list" :: what :: _ -> list_cmd transport what meta
  | "call" :: tool :: rest ->
      let args_json =
        let rec find_args = function
          | [] -> None
          | ("-a" | "--args") :: json :: _ -> Some json
          | _ :: rest -> find_args rest
        in
        find_args rest
      in
      call_cmd transport tool args_json meta
  | "read" :: uri :: _ -> read_cmd transport uri meta
  | "info" :: _ -> info_cmd transport
  | _ -> print_usage ()
