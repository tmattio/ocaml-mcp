(** MCP SDK with Eio async support.

    This module provides async versions of the MCP SDK handlers, allowing
    handlers to return Eio promises for non-blocking operations. *)

module Async_context = struct
  include Mcp_sdk.Context

  (** Create an async context that can report progress asynchronously *)
  let report_progress_async t ~sw ~progress ?total () =
    Eio.Fiber.fork ~sw (fun () -> report_progress t ~progress ?total ())
end

module Async_server = struct
  type handler_info = {
    name : string; [@warning "-69"]
    title : string option;
    description : string option;
  }

  type async_tool_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    output_schema : Yojson.Safe.t option;
    annotations : Mcp.Types.Tool.annotation option;
    handler :
      Yojson.Safe.t option ->
      Async_context.t ->
      (Mcp.Request.Tools.Call.result, string) result Eio.Promise.t;
  }

  type async_resource_handler =
    | StaticResource of {
        info : handler_info;
        uri : string;
        mime_type : string option;
        handler :
          string ->
          Async_context.t ->
          (Mcp.Request.Resources.Read.result, string) result Eio.Promise.t;
      }
    | TemplateResource of {
        info : handler_info;
        template : string;
        mime_type : string option;
        list_handler :
          (Async_context.t ->
          (Mcp.Request.Resources.List.result, string) result Eio.Promise.t)
          option;
        read_handler :
          (string * string) list ->
          Async_context.t ->
          (Mcp.Request.Resources.Read.result, string) result Eio.Promise.t;
      }

  type async_prompt_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    handler :
      Yojson.Safe.t option ->
      Async_context.t ->
      (Mcp.Request.Prompts.Get.result, string) result Eio.Promise.t;
  }

  type async_subscription_handler = {
    on_subscribe :
      string -> Async_context.t -> (unit, string) result Eio.Promise.t;
    on_unsubscribe :
      string -> Async_context.t -> (unit, string) result Eio.Promise.t;
  }

  type t = {
    server_info : Mcp.Types.ServerInfo.t;
    mutable capabilities : Mcp.Types.Capabilities.server;
    tools : (string, async_tool_handler) Hashtbl.t;
    resources : (string, async_resource_handler) Hashtbl.t;
    prompts : (string, async_prompt_handler) Hashtbl.t;
    mutable subscription_handler : async_subscription_handler option;
    pagination_config : Mcp_sdk.Server.pagination_config option;
    mcp_logging_config : Mcp_sdk.Server.mcp_logging_config;
  }

  let create ~server_info ?capabilities ?pagination_config ?mcp_logging_config
      () =
    let capabilities =
      match capabilities with
      | Some c -> c
      | None ->
          {
            Mcp.Types.Capabilities.experimental = None;
            logging = None;
            prompts = None;
            resources = None;
            tools = None;
            completions = None;
          }
    in
    let mcp_logging_config =
      match mcp_logging_config with
      | Some c -> c
      | None -> { Mcp_sdk.Server.enabled = true; initial_level = None }
    in
    {
      server_info;
      capabilities;
      tools = Hashtbl.create 16;
      resources = Hashtbl.create 16;
      prompts = Hashtbl.create 16;
      subscription_handler = None;
      pagination_config;
      mcp_logging_config;
    }

  (** Register an async tool handler *)
  let tool : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?output_schema:Yojson.Safe.t ->
      ?annotations:Mcp.Types.Tool.annotation ->
      ?args:(module Mcp_sdk.Server.Json_converter with type t = a) ->
      (a ->
      Async_context.t ->
      (Mcp.Request.Tools.Call.result, string) result Eio.Promise.t) ->
      unit =
   fun t name ?title ?description ?output_schema ?annotations ?args handler ->
    let schema =
      match args with
      | None -> Some (`Assoc [ ("type", `String "object") ])
      | Some (module Args) -> Some (Args.schema ())
    in

    (* Validate schemas at registration time *)
    let validate_schema schema_opt name_suffix =
      match schema_opt with
      | Some schema -> (
          let basic_schema = Yojson.Safe.to_basic schema in
          match
            Jsonschema.create_validator_from_json ~schema:basic_schema ()
          with
          | Error err ->
              Some
                (Format.asprintf "Invalid %s for tool '%s': %a" name_suffix name
                   Jsonschema.pp_compile_error err)
          | Ok _ -> None)
      | None -> None
    in

    let input_error = validate_schema schema "input schema" in
    let output_error = validate_schema output_schema "output schema" in
    let schema_error =
      match (input_error, output_error) with
      | Some err, _ -> Some err
      | _, Some err -> Some err
      | None, None -> None
    in

    let typed_handler json_opt ctx =
      match schema_error with
      | Some err -> Eio.Promise.create_resolved (Error err)
      | None -> (
          match args with
          | None ->
              (Obj.magic handler
                : unit ->
                  Async_context.t ->
                  (Mcp.Request.Tools.Call.result, string) result Eio.Promise.t)
                () ctx
          | Some (module Args) -> (
              let json = Option.value json_opt ~default:(`Assoc []) in
              match Args.of_yojson json with
              | Ok args -> handler args ctx
              | Error e ->
                  Eio.Promise.create_resolved
                    (Error ("Failed to parse arguments: " ^ e))))
    in

    let th : async_tool_handler =
      {
        info = { name; title; description };
        schema;
        output_schema;
        annotations;
        handler = typed_handler;
      }
    in
    Hashtbl.replace t.tools name th;
    t.capabilities <-
      { t.capabilities with tools = Some { list_changed = Some false } }

  (** Register an async resource handler *)
  let resource t name ~uri ?description ?mime_type handler =
    let resource_handler =
      StaticResource
        { info = { name; title = None; description }; uri; mime_type; handler }
    in
    Hashtbl.replace t.resources name resource_handler;
    t.capabilities <-
      {
        t.capabilities with
        resources =
          Some
            {
              subscribe = Option.map (fun _ -> true) t.subscription_handler;
              list_changed = None;
            };
      }

  (** Register an async resource template handler *)
  let resource_template t name ~template ?description ?mime_type ?list_handler
      read_handler =
    let resource_handler =
      TemplateResource
        {
          info = { name; title = None; description };
          template;
          mime_type;
          list_handler;
          read_handler;
        }
    in
    Hashtbl.replace t.resources name resource_handler;
    t.capabilities <-
      {
        t.capabilities with
        resources =
          Some
            {
              subscribe = Option.map (fun _ -> true) t.subscription_handler;
              list_changed = None;
            };
      }

  (** Register an async prompt handler *)
  let prompt : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?args:(module Mcp_sdk.Server.Json_converter with type t = a) ->
      (a ->
      Async_context.t ->
      (Mcp.Request.Prompts.Get.result, string) result Eio.Promise.t) ->
      unit =
   fun t name ?title ?description ?args handler ->
    let schema =
      match args with
      | None -> None
      | Some (module Args) -> Some (Args.schema ())
    in

    let typed_handler json_opt ctx =
      match args with
      | None ->
          (Obj.magic handler
            : unit ->
              Async_context.t ->
              (Mcp.Request.Prompts.Get.result, string) result Eio.Promise.t)
            () ctx
      | Some (module Args) -> (
          let json = Option.value json_opt ~default:(`Assoc []) in
          match Args.of_yojson json with
          | Ok args -> handler args ctx
          | Error e ->
              Eio.Promise.create_resolved
                (Error ("Failed to parse arguments: " ^ e)))
    in

    let ph : async_prompt_handler =
      { info = { name; title; description }; schema; handler = typed_handler }
    in
    Hashtbl.replace t.prompts name ph;
    t.capabilities <-
      { t.capabilities with prompts = Some { list_changed = None } }

  (** Set async subscription handlers *)
  let set_subscription_handler t ~on_subscribe ~on_unsubscribe =
    t.subscription_handler <- Some { on_subscribe; on_unsubscribe };
    t.capabilities <-
      {
        t.capabilities with
        resources =
          Some
            {
              subscribe = Some true;
              list_changed =
                (match t.capabilities.resources with
                | Some r -> r.list_changed
                | None -> None);
            };
      }

  (** Convert async server to synchronous MCP server *)
  let to_mcp_server ~sw:_ t =
    (* Create a synchronous server that wraps our async handlers *)
    let sync_server =
      Mcp_sdk.Server.create ~server_info:t.server_info
        ~capabilities:t.capabilities ?pagination_config:t.pagination_config
        ~mcp_logging_config:t.mcp_logging_config ()
    in

    (* Register sync wrappers for all async tools *)
    Hashtbl.iter
      (fun name (handler : async_tool_handler) ->
        (* Register using the public API based on whether there's a schema *)
        match handler.schema with
        | Some schema when schema <> `Assoc [ ("type", `String "object") ] ->
            (* Tool with arguments - use a JSON passthrough converter *)
            let json_converter =
              (module struct
                type t = Yojson.Safe.t

                let to_yojson x = x
                let of_yojson x = Ok x
                let schema () = schema
              end : Mcp_sdk.Server.Json_converter
                with type t = Yojson.Safe.t)
            in

            let sync_handler json ctx =
              let promise = handler.handler (Some json) ctx in
              Eio.Promise.await promise
            in

            Mcp_sdk.Server.tool sync_server name ?title:handler.info.title
              ?description:handler.info.description
              ?output_schema:handler.output_schema
              ?annotations:handler.annotations ~args:json_converter sync_handler
        | _ ->
            (* Tool with no arguments or empty object schema *)
            let sync_handler () ctx =
              let promise = handler.handler None ctx in
              Eio.Promise.await promise
            in

            Mcp_sdk.Server.tool sync_server name ?title:handler.info.title
              ?description:handler.info.description
              ?output_schema:handler.output_schema
              ?annotations:handler.annotations sync_handler)
      t.tools;

    (* Register sync wrappers for all async resources *)
    Hashtbl.iter
      (fun name handler ->
        match handler with
        | StaticResource r ->
            let sync_handler uri ctx =
              let promise = r.handler uri ctx in
              Eio.Promise.await promise
            in
            Mcp_sdk.Server.resource sync_server name ~uri:r.uri
              ?description:r.info.description ?mime_type:r.mime_type
              sync_handler
        | TemplateResource r ->
            let sync_list_handler =
              match r.list_handler with
              | None -> None
              | Some h ->
                  Some
                    (fun ctx ->
                      let promise = h ctx in
                      Eio.Promise.await promise)
            in
            let sync_read_handler vars ctx =
              let promise = r.read_handler vars ctx in
              Eio.Promise.await promise
            in
            Mcp_sdk.Server.resource_template sync_server name
              ~template:r.template ?description:r.info.description
              ?mime_type:r.mime_type ?list_handler:sync_list_handler
              sync_read_handler)
      t.resources;

    (* Register sync wrappers for all async prompts *)
    Hashtbl.iter
      (fun name (handler : async_prompt_handler) ->
        match handler.schema with
        | Some schema ->
            (* Prompt with arguments *)
            let json_converter =
              (module struct
                type t = Yojson.Safe.t

                let to_yojson x = x
                let of_yojson x = Ok x
                let schema () = schema
              end : Mcp_sdk.Server.Json_converter
                with type t = Yojson.Safe.t)
            in

            let sync_handler json ctx =
              let promise = handler.handler (Some json) ctx in
              Eio.Promise.await promise
            in

            Mcp_sdk.Server.prompt sync_server name ?title:handler.info.title
              ?description:handler.info.description ~args:json_converter
              sync_handler
        | None ->
            (* Prompt with no arguments *)
            let sync_handler () ctx =
              let promise = handler.handler None ctx in
              Eio.Promise.await promise
            in

            Mcp_sdk.Server.prompt sync_server name ?title:handler.info.title
              ?description:handler.info.description sync_handler)
      t.prompts;

    (* Register sync wrappers for subscription handlers *)
    (match t.subscription_handler with
    | None -> ()
    | Some h ->
        let sync_on_subscribe uri ctx =
          let promise = h.on_subscribe uri ctx in
          Eio.Promise.await promise
        in
        let sync_on_unsubscribe uri ctx =
          let promise = h.on_unsubscribe uri ctx in
          Eio.Promise.await promise
        in
        Mcp_sdk.Server.set_subscription_handler sync_server
          ~on_subscribe:sync_on_subscribe ~on_unsubscribe:sync_on_unsubscribe);

    (* Convert to MCP server *)
    Mcp_sdk.Server.to_mcp_server sync_server

  (** Set up MCP logging if enabled *)
  let setup_mcp_logging t mcp_server =
    if t.mcp_logging_config.enabled then (
      (* Set initial MCP log level if specified *)
      (match t.mcp_logging_config.initial_level with
      | Some level ->
          let ocaml_level = Mcp_sdk.Logging.map_mcp_to_logs_level level in
          Logs.set_level ocaml_level
      | None -> ());

      (* Create notification sender *)
      let send_notification notif =
        let _msg = Mcp.Server.send_notification mcp_server notif in
        ()
      in

      (* Add MCP notifier to existing reporter *)
      let current_reporter = Logs.reporter () in
      let combined_reporter =
        Mcp_sdk.Logging.add_mcp_notifier ~send_notification current_reporter
      in
      Logs.set_reporter combined_reporter;
      Logs_threaded.enable ();

      Logs.info (fun m -> m "MCP logging enabled"))

  (** Run an async server with Eio *)
  let run ~sw ~env:_ t connection =
    let mcp_server = to_mcp_server ~sw t in
    (* Set up MCP logging using SDK functionality *)
    setup_mcp_logging t mcp_server;
    Mcp_eio.Connection.serve ~sw connection mcp_server
end

module Context = Async_context
(** Convenience module aliases *)

module Server = Async_server

(** Helper to create Eio promises *)
let async result = Eio.Promise.create_resolved result

let async_ok value = async (Ok value)
let async_error msg = async (Error msg)
