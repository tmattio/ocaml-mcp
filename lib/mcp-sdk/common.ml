(** Common SDK implementation using functors to support both sync and async *)

module Types = Mcp.Types
module Protocol = Mcp.Protocol

(* Setup logging *)
let src = Logs.Src.create "mcp.sdk" ~doc:"MCP SDK logging"

module Log = (val Logs.src_log src : Logs.LOG)

module Context = struct
  type t = {
    req_id : Types.request_id;
    prog_token : Types.progress_token option;
    send_notif : Mcp.Notification.t -> unit;
    meta : Yojson.Safe.t option;
  }

  let request_id t = t.req_id
  let progress_token t = t.prog_token
  let send_notification t notif = t.send_notif notif
  let meta t = t.meta

  let report_progress t ~progress ?total () =
    match t.prog_token with
    | None -> ()
    | Some token ->
        let progress_params =
          { Mcp.Notification.Progress.progress_token = token; progress; total }
        in
        send_notification t (Mcp.Notification.Progress progress_params)
end

module Tool_result = struct
  let create ?content ?structured_content ?is_error () =
    {
      Mcp.Request.Tools.Call.content = Option.value content ~default:[];
      Mcp.Request.Tools.Call.structured_content;
      Mcp.Request.Tools.Call.is_error;
      Mcp.Request.Tools.Call.meta = None;
    }

  let text s =
    create
      ~content:
        [ Mcp.Types.Content.Text { type_ = "text"; text = s; meta = None } ]
      ()

  let error msg =
    create
      ~content:
        [ Mcp.Types.Content.Text { type_ = "text"; text = msg; meta = None } ]
      ~is_error:true ()

  let structured ?text json =
    let content =
      match text with
      | None -> []
      | Some t ->
          [ Mcp.Types.Content.Text { type_ = "text"; text = t; meta = None } ]
    in
    create ~content ~structured_content:json ()
end

module Logging = struct
  let map_mcp_to_logs_level = function
    | Mcp.Types.LogLevel.Debug -> Some Logs.Debug
    | Info -> Some Logs.Info
    | Notice -> Some Logs.Info
    | Warning -> Some Logs.Warning
    | Error -> Some Logs.Error
    | Critical -> Some Logs.Error
    | Alert -> Some Logs.Error
    | Emergency -> Some Logs.Error

  let send_log_notification ~send_notification ~src ~level ~msg =
    let mcp_level =
      match level with
      | Logs.App -> Mcp.Types.LogLevel.Info
      | Logs.Error -> Mcp.Types.LogLevel.Error
      | Logs.Warning -> Mcp.Types.LogLevel.Warning
      | Logs.Info -> Mcp.Types.LogLevel.Info
      | Logs.Debug -> Mcp.Types.LogLevel.Debug
    in
    let logger = Logs.Src.name src in
    let data =
      `Assoc
        [
          ("message", `String msg);
          ("timestamp", `String (string_of_float (Unix.time ())));
        ]
    in
    let params =
      { Mcp.Notification.Message.level = mcp_level; logger = Some logger; data }
    in
    try send_notification (Mcp.Notification.Message params) with _ -> ()

  let combine_reporter r1 r2 =
    let report src level ~over k msgf =
      let v = r1.Logs.report src level ~over:(fun () -> ()) k msgf in
      r2.Logs.report src level ~over (fun () -> v) msgf
    in
    { Logs.report }

  let mcp_notifier ~send_notification =
    let report src level ~over k msgf =
      let k' () =
        over ();
        k ()
      in
      msgf @@ fun ?header:_ ?tags:_ fmt ->
      Format.kasprintf
        (fun msg ->
          send_log_notification ~send_notification ~src ~level ~msg;
          k' ())
        fmt
    in
    { Logs.report }

  let add_mcp_notifier ~send_notification existing_reporter =
    combine_reporter existing_reporter (mcp_notifier ~send_notification)
end

(** The Monad signature defines the computational context for handlers *)
module type Io = sig
  type 'a t

  val return : 'a -> 'a t
  val map : ('a -> 'b) -> 'a t -> 'b t
  val run : 'a t -> 'a
end

module type Json_converter = sig
  type t

  val to_yojson : t -> Yojson.Safe.t
  val of_yojson : Yojson.Safe.t -> (t, string) result
  val schema : unit -> Yojson.Safe.t
end

(** Functor for creating SDK servers with different computational contexts *)
module Make (M : Io) = struct
  type handler_info = {
    name : string;
    title : string option;
    description : string option;
  }

  type tool_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    output_schema : Yojson.Safe.t option;
    annotations : Mcp.Types.Tool.annotation option;
    handler :
      Yojson.Safe.t option ->
      Context.t ->
      (Mcp.Request.Tools.Call.result, string) result M.t;
  }

  type resource_handler =
    | StaticResource of {
        info : handler_info;
        uri : string;
        mime_type : string option;
        handler :
          string ->
          Context.t ->
          (Mcp.Request.Resources.Read.result, string) result M.t;
      }
    | TemplateResource of {
        info : handler_info;
        template : string;
        mime_type : string option;
        list_handler :
          (Context.t -> (Mcp.Request.Resources.List.result, string) result M.t)
          option;
        read_handler :
          (string * string) list ->
          Context.t ->
          (Mcp.Request.Resources.Read.result, string) result M.t;
      }

  type prompt_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    handler :
      Yojson.Safe.t option ->
      Context.t ->
      (Mcp.Request.Prompts.Get.result, string) result M.t;
  }

  type subscription_handler = {
    on_subscribe : string -> Context.t -> (unit, string) result M.t;
    on_unsubscribe : string -> Context.t -> (unit, string) result M.t;
  }

  type pagination_config = { page_size : int }

  type mcp_logging_config = {
    enabled : bool;
    initial_level : Types.LogLevel.t option;
  }

  type t = {
    server_info : Types.ServerInfo.t;
    mutable capabilities : Types.Capabilities.server;
    tools : (string, tool_handler) Hashtbl.t;
    resources : (string, resource_handler) Hashtbl.t;
    prompts : (string, prompt_handler) Hashtbl.t;
    mutable subscription_handler : subscription_handler option;
    pagination_config : pagination_config option;
    mcp_logging_config : mcp_logging_config;
  }

  let create ~server_info
      ?(capabilities =
        {
          Types.Capabilities.experimental = None;
          logging = None;
          prompts = None;
          resources = None;
          tools = None;
          completions = None;
        }) ?pagination_config
      ?(mcp_logging_config = { enabled = true; initial_level = None }) () =
    let capabilities =
      if mcp_logging_config.enabled then
        {
          capabilities with
          logging = Some (`Assoc [ ("enabled", `Bool true) ]);
        }
      else capabilities
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

  (* Helper function for tools with no arguments *)
  let tool_no_args t name ?title ?description ?output_schema ?annotations
      handler =
    let output_schema_error =
      match output_schema with
      | Some out_schema -> (
          let basic_out_schema = Yojson.Safe.to_basic out_schema in
          match
            Jsonschema.create_validator_from_json ~schema:basic_out_schema ()
          with
          | Error err ->
              Some
                (Format.asprintf "Invalid output schema for tool '%s': %a" name
                   Jsonschema.pp_compile_error err)
          | Ok _ -> None)
      | None -> None
    in
    let typed_handler json_opt ctx =
      match output_schema_error with
      | Some err -> M.return (Error err)
      | None ->
          let _ = json_opt in
          M.map
            (fun result ->
              match (result, output_schema) with
              | Ok res, Some schema
                when res.Mcp.Request.Tools.Call.structured_content <> None -> (
                  let content =
                    Option.get res.Mcp.Request.Tools.Call.structured_content
                  in
                  let basic_content = Yojson.Safe.to_basic content in
                  let basic_schema = Yojson.Safe.to_basic schema in
                  match
                    Jsonschema.create_validator_from_json ~schema:basic_schema
                      ()
                  with
                  | Error err ->
                      Error
                        (Format.asprintf "Invalid output schema: %a"
                           Jsonschema.pp_compile_error err)
                  | Ok validator -> (
                      match Jsonschema.validate validator basic_content with
                      | Ok () -> result
                      | Error error ->
                          Error
                            (Printf.sprintf "Output validation failed: %s"
                               (Jsonschema.Validation_error.to_string error))))
              | _ -> result)
            (handler () ctx)
    in
    let th : tool_handler =
      {
        info = { name; title; description };
        schema = Some (`Assoc [ ("type", `String "object") ]);
        output_schema;
        annotations;
        handler = typed_handler;
      }
    in
    Hashtbl.replace t.tools name th;
    t.capabilities <-
      { t.capabilities with tools = Some { list_changed = Some false } }

  let tool : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?output_schema:Yojson.Safe.t ->
      ?annotations:Mcp.Types.Tool.annotation ->
      ?args:(module Json_converter with type t = a) ->
      (a -> Context.t -> (Mcp.Request.Tools.Call.result, string) result M.t) ->
      unit =
   fun t name ?title ?description ?output_schema ?annotations ?args handler ->
    match args with
    | None ->
        tool_no_args t name ?title ?description ?output_schema ?annotations
          (Obj.magic handler)
    | Some (module Args : Json_converter with type t = a) ->
        let schema = Args.schema () in
        let basic_schema = Yojson.Safe.to_basic schema in
        let input_schema_error =
          match
            Jsonschema.create_validator_from_json ~schema:basic_schema ()
          with
          | Error err ->
              Some
                (Format.asprintf "Invalid input schema for tool '%s': %a" name
                   Jsonschema.pp_compile_error err)
          | Ok _ -> None
        in
        let output_schema_error =
          match output_schema with
          | Some out_schema -> (
              let basic_out_schema = Yojson.Safe.to_basic out_schema in
              match
                Jsonschema.create_validator_from_json ~schema:basic_out_schema
                  ()
              with
              | Error err ->
                  Some
                    (Format.asprintf "Invalid output schema for tool '%s': %a"
                       name Jsonschema.pp_compile_error err)
              | Ok _ -> None)
          | None -> None
        in
        let schema_error =
          match (input_schema_error, output_schema_error) with
          | Some err, _ -> Some err
          | _, Some err -> Some err
          | None, None -> None
        in
        let typed_handler json_opt ctx =
          match schema_error with
          | Some err -> M.return (Error err)
          | None -> (
              let json = Option.value json_opt ~default:(`Assoc []) in
              let basic_json = Yojson.Safe.to_basic json in
              match
                Jsonschema.create_validator_from_json ~schema:basic_schema ()
              with
              | Error err ->
                  M.return
                    (Error
                       (Format.asprintf "Invalid input schema: %a"
                          Jsonschema.pp_compile_error err))
              | Ok validator -> (
                  match Jsonschema.validate validator basic_json with
                  | Error error ->
                      M.return
                        (Error
                           (Printf.sprintf "Input validation failed: %s"
                              (Jsonschema.Validation_error.to_string error)))
                  | Ok () -> (
                      match Args.of_yojson json with
                      | Ok args ->
                          M.map
                            (fun result ->
                              match (result, output_schema) with
                              | Ok res, Some schema
                                when res
                                       .Mcp.Request.Tools.Call
                                        .structured_content <> None -> (
                                  let content =
                                    Option.get
                                      res
                                        .Mcp.Request.Tools.Call
                                         .structured_content
                                  in
                                  let basic_content =
                                    Yojson.Safe.to_basic content
                                  in
                                  let basic_schema =
                                    Yojson.Safe.to_basic schema
                                  in
                                  match
                                    Jsonschema.create_validator_from_json
                                      ~schema:basic_schema ()
                                  with
                                  | Error err ->
                                      Error
                                        (Format.asprintf
                                           "Invalid output schema: %a"
                                           Jsonschema.pp_compile_error err)
                                  | Ok validator -> (
                                      match
                                        Jsonschema.validate validator
                                          basic_content
                                      with
                                      | Ok () -> result
                                      | Error error ->
                                          Error
                                            (Printf.sprintf
                                               "Output validation failed: %s"
                                               (Jsonschema.Validation_error
                                                .to_string error))))
                              | _ -> result)
                            (handler args ctx)
                      | Error e ->
                          M.return (Error ("Failed to parse arguments: " ^ e))))
              )
        in
        let th : tool_handler =
          {
            info = { name; title; description };
            schema = Some schema;
            output_schema;
            annotations;
            handler = typed_handler;
          }
        in
        Hashtbl.replace t.tools name th;
        t.capabilities <-
          { t.capabilities with tools = Some { list_changed = Some false } }

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

  let prompt_no_args t name ?title ?description handler =
    let typed_handler _ ctx = handler () ctx in
    let ph =
      {
        info = { name; title; description };
        schema = None;
        handler = typed_handler;
      }
    in
    Hashtbl.replace t.prompts name ph;
    t.capabilities <-
      { t.capabilities with prompts = Some { list_changed = Some false } }

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

  let prompt : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?args:(module Json_converter with type t = a) ->
      (a -> Context.t -> (Mcp.Request.Prompts.Get.result, string) result M.t) ->
      unit =
   fun t name ?title ?description ?args handler ->
    match args with
    | None -> prompt_no_args t name ?title ?description (Obj.magic handler)
    | Some (module Args : Json_converter with type t = a) ->
        let schema = Args.schema () in
        let typed_handler json_opt ctx =
          let json = Option.value json_opt ~default:(`Assoc []) in
          match Args.of_yojson json with
          | Ok args -> handler args ctx
          | Error e -> M.return (Error ("Failed to parse arguments: " ^ e))
        in
        let ph : prompt_handler =
          {
            info = { name; title; description };
            schema = Some schema;
            handler = typed_handler;
          }
        in
        Hashtbl.replace t.prompts name ph;
        t.capabilities <-
          { t.capabilities with prompts = Some { list_changed = None } }

  (* Pagination helpers *)
  let decode_cursor cursor =
    try
      match Base64.decode cursor with
      | Ok s -> (
          match int_of_string_opt s with
          | Some n -> Ok n
          | None -> Error "Invalid cursor format")
      | Error _ -> Error "Failed to decode cursor"
    with _ -> Error "Invalid cursor"

  let encode_cursor offset = Base64.encode_string (string_of_int offset)

  let paginate_list items cursor page_size =
    let start_offset =
      match cursor with
      | None -> 0
      | Some c -> ( match decode_cursor c with Ok n -> n | Error _ -> 0)
    in
    let total_items = List.length items in
    let items_array = Array.of_list items in
    let end_offset = min (start_offset + page_size) total_items in
    let page_items =
      if start_offset < total_items then
        Array.sub items_array start_offset (end_offset - start_offset)
        |> Array.to_list
      else []
    in
    let next_cursor =
      if end_offset < total_items then Some (encode_cursor end_offset) else None
    in
    (page_items, next_cursor)

  let parse_uri_template template uri =
    let var_regex = Re.Perl.compile_pat "\\{([^}]+)\\}" in
    let vars =
      Re.all var_regex template |> List.map (fun g -> Re.Group.get g 1)
    in
    let pattern =
      template
      |> Re.replace_string (Re.Perl.compile_pat "\\{[^}]+\\}") ~by:"([^/]+)"
      |> Re.Perl.re |> Re.compile
    in
    match Re.exec_opt pattern uri with
    | None -> None
    | Some groups -> (
        try
          let values =
            List.mapi (fun i var -> (var, Re.Group.get groups (i + 1))) vars
          in
          Some values
        with Not_found -> None)

  let to_mcp_server t =
    let send_notification_ref = ref (fun _ -> ()) in

    let make_context req_id prog_token meta =
      { Context.req_id; prog_token; send_notif = !send_notification_ref; meta }
    in

    let handler =
      {
        Mcp.Server.default_handler with
        on_initialize =
          (fun _params ->
            Ok
              {
                Mcp.Request.Initialize.protocol_version =
                  Mcp.Types.Protocol.default_negotiated_version;
                capabilities = t.capabilities;
                server_info = t.server_info;
                instructions = None;
                meta = None;
              });
        on_tools_list =
          (fun params ->
            let all_tools =
              Hashtbl.fold
                (fun _name (h : tool_handler) acc ->
                  {
                    Mcp.Types.Tool.name = h.info.name;
                    title = h.info.title;
                    description = h.info.description;
                    input_schema = Option.value ~default:(`Assoc []) h.schema;
                    output_schema = h.output_schema;
                    annotations = h.annotations;
                    meta = None;
                  }
                  :: acc)
                t.tools []
            in
            match t.pagination_config with
            | None -> Ok { tools = all_tools; next_cursor = None; meta = None }
            | Some config ->
                let tools, next_cursor =
                  paginate_list all_tools params.cursor config.page_size
                in
                Ok { tools; next_cursor; meta = None });
        on_tools_call =
          (fun params ->
            match Hashtbl.find_opt t.tools params.name with
            | None ->
                Log.err (fun m -> m "Unknown tool: %s" params.name);
                Error ("Unknown tool: " ^ params.name)
            | Some h ->
                let ctx = make_context (String "tool-call") None params.meta in
                let result = M.run (h.handler params.arguments ctx) in
                (match result with
                | Ok _ ->
                    Log.info (fun m ->
                        m "Tool %s executed successfully" params.name)
                | Error e ->
                    Log.err (fun m -> m "Tool %s failed: %s" params.name e));
                result);
        on_resources_list =
          (fun params ->
            let all_resources =
              Hashtbl.fold
                (fun _name (handler : resource_handler) acc ->
                  match handler with
                  | StaticResource r ->
                      {
                        Mcp.Types.Resource.uri = r.uri;
                        name = r.info.name;
                        mime_type = r.mime_type;
                        title = r.info.title;
                        description = r.info.description;
                        size = None;
                        annotations = None;
                        meta = None;
                      }
                      :: acc
                  | TemplateResource r -> (
                      match r.list_handler with
                      | None -> acc
                      | Some list_fn -> (
                          let ctx =
                            make_context (String "resource-list") None
                              params.meta
                          in
                          match M.run (list_fn ctx) with
                          | Ok result ->
                              result.Mcp.Request.Resources.List.resources @ acc
                          | Error _ -> acc)))
                t.resources []
            in
            match t.pagination_config with
            | None ->
                Ok
                  { resources = all_resources; next_cursor = None; meta = None }
            | Some config ->
                let resources, next_cursor =
                  paginate_list all_resources params.cursor config.page_size
                in
                Ok { resources; next_cursor; meta = None });
        on_resources_templates_list =
          (fun _params ->
            let templates =
              Hashtbl.fold
                (fun _name handler acc ->
                  match handler with
                  | StaticResource _ -> acc
                  | TemplateResource r ->
                      {
                        Mcp.Types.Resource.uri_template = r.template;
                        name = r.info.name;
                        mime_type = r.mime_type;
                        title = r.info.title;
                        description = r.info.description;
                        annotations = None;
                        meta = None;
                      }
                      :: acc)
                t.resources []
            in
            Ok
              {
                resource_templates = templates;
                next_cursor = None;
                meta = None;
              });
        on_resources_read =
          (fun (params : Mcp.Request.Resources.Read.params) ->
            let find_and_run_static () :
                (Mcp.Request.Resources.Read.result, string) result option =
              Hashtbl.fold
                (fun _name handler acc ->
                  match acc with
                  | Some _ -> acc
                  | None -> (
                      match handler with
                      | StaticResource { uri; handler = h; _ }
                        when uri = params.uri ->
                          let ctx =
                            make_context (String "resource-read") None
                              params.meta
                          in
                          let res = h params.uri ctx in
                          Some (M.run res)
                      | _ -> None))
                t.resources None
            in
            let find_and_run_template () :
                (Mcp.Request.Resources.Read.result, string) result option =
              Hashtbl.fold
                (fun _name handler acc ->
                  match acc with
                  | Some _ -> acc
                  | None -> (
                      match handler with
                      | TemplateResource { template; read_handler; _ } -> (
                          match parse_uri_template template params.uri with
                          | Some vars ->
                              let ctx =
                                make_context (String "resource-read") None
                                  params.meta
                              in
                              let res = read_handler vars ctx in
                              Some (M.run res)
                          | None -> None)
                      | _ -> None))
                t.resources None
            in
            match find_and_run_static () with
            | Some result -> result
            | None -> (
                match find_and_run_template () with
                | Some result -> result
                | None -> Error ("Resource not found: " ^ params.uri)));
        on_prompts_list =
          (fun params ->
            let all_prompts =
              Hashtbl.fold
                (fun _name h acc ->
                  {
                    Mcp.Types.Prompt.name = h.info.name;
                    title = h.info.title;
                    description = h.info.description;
                    arguments =
                      (match h.schema with
                      | Some _s ->
                          Some
                            [
                              {
                                Mcp.Types.Prompt.name = "args";
                                title = None;
                                description = None;
                                required = Some true;
                              };
                            ]
                      | None -> None);
                    meta = None;
                  }
                  :: acc)
                t.prompts []
            in
            match t.pagination_config with
            | None ->
                Ok { prompts = all_prompts; next_cursor = None; meta = None }
            | Some config ->
                let prompts, next_cursor =
                  paginate_list all_prompts params.cursor config.page_size
                in
                Ok { prompts; next_cursor; meta = None });
        on_prompts_get =
          (fun params ->
            match Hashtbl.find_opt t.prompts params.name with
            | None -> Error ("Unknown prompt: " ^ params.name)
            | Some h ->
                let ctx = make_context (String "prompt-get") None params.meta in
                let json_args =
                  match params.arguments with
                  | None -> None
                  | Some args ->
                      Some
                        (`Assoc (List.map (fun (k, v) -> (k, `String v)) args))
                in
                M.run (h.handler json_args ctx));
        on_resources_subscribe =
          (fun params ->
            match t.subscription_handler with
            | None -> Error "Resource subscriptions not supported"
            | Some handler ->
                let ctx =
                  make_context (String "resource-subscribe") None params.meta
                in
                M.run (handler.on_subscribe params.uri ctx));
        on_resources_unsubscribe =
          (fun params ->
            match t.subscription_handler with
            | None -> Error "Resource subscriptions not supported"
            | Some handler ->
                let ctx =
                  make_context (String "resource-unsubscribe") None params.meta
                in
                M.run (handler.on_unsubscribe params.uri ctx));
        on_logging_set_level =
          (fun params ->
            let ocaml_level = Logging.map_mcp_to_logs_level params.level in
            Logs.set_level ocaml_level;
            Log.info (fun m ->
                m "MCP log level set to %s"
                  (Yojson.Safe.to_string
                     (Mcp.Types.LogLevel.to_yojson params.level)));
            Ok { meta = None });
      }
    in

    let notification_handler = Mcp.Server.default_notification_handler in

    let server =
      Mcp.Server.create ~handler ~notification_handler
        ~server_info:t.server_info ~server_capabilities:t.capabilities
    in

    (send_notification_ref :=
       fun notif ->
         let _msg = Mcp.Server.send_notification server notif in
         ());

    server

  let setup_mcp_logging t mcp_server =
    if t.mcp_logging_config.enabled then (
      (match t.mcp_logging_config.initial_level with
      | Some level ->
          let ocaml_level = Logging.map_mcp_to_logs_level level in
          Logs.set_level ocaml_level
      | None -> ());

      let send_notification notif =
        let _msg = Mcp.Server.send_notification mcp_server notif in
        ()
      in

      let current_reporter = Logs.reporter () in
      let combined_reporter =
        Logging.add_mcp_notifier ~send_notification current_reporter
      in
      Logs.set_reporter combined_reporter;
      Logs_threaded.enable ();

      Log.info (fun m -> m "MCP logging enabled"))
end
