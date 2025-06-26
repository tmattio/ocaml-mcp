module Types = Mcp.Types
module Protocol = Mcp.Protocol

module Context = struct
  type t = {
    req_id : Types.request_id;
    prog_token : Types.progress_token option;
    send_notif : Mcp.Notification.t -> unit;
  }

  let request_id t = t.req_id
  let progress_token t = t.prog_token
  let send_notification t notif = t.send_notif notif
end

module Server = struct
  type handler_info = {
    name : string;
    title : string option;
    description : string option;
  }

  type tool_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    handler :
      Yojson.Safe.t option ->
      Context.t ->
      (Mcp.Request.Tools.Call.result, string) result;
  }

  type resource_handler =
    | StaticResource of {
        info : handler_info;
        uri : string;
        mime_type : string option;
        handler :
          string ->
          Context.t ->
          (Mcp.Request.Resources.Read.result, string) result;
      }
    | TemplateResource of {
        info : handler_info;
        template : string;
        mime_type : string option;
        list_handler :
          (Context.t -> (Mcp.Request.Resources.List.result, string) result)
          option;
        read_handler :
          (string * string) list ->
          Context.t ->
          (Mcp.Request.Resources.Read.result, string) result;
      }

  type prompt_handler = {
    info : handler_info;
    schema : Yojson.Safe.t option;
    handler :
      Yojson.Safe.t option ->
      Context.t ->
      (Mcp.Request.Prompts.Get.result, string) result;
  }

  type t = {
    server_info : Types.ServerInfo.t;
    mutable capabilities : Types.Capabilities.server;
    tools : (string, tool_handler) Hashtbl.t;
    resources : (string, resource_handler) Hashtbl.t;
    prompts : (string, prompt_handler) Hashtbl.t;
  }

  module type Json_converter = sig
    type t

    val to_yojson : t -> Yojson.Safe.t
    val of_yojson : Yojson.Safe.t -> (t, string) result
    val schema : unit -> Yojson.Safe.t
  end

  let create ~server_info
      ?(capabilities =
        {
          Types.Capabilities.experimental = None;
          logging = None;
          prompts = None;
          resources = None;
          tools = None;
          completions = None;
        }) () =
    {
      server_info;
      capabilities;
      tools = Hashtbl.create 16;
      resources = Hashtbl.create 16;
      prompts = Hashtbl.create 16;
    }

  (* Helper function for tools with no arguments *)
  let tool_no_args t name ?title ?description handler =
    let typed_handler _ ctx = handler () ctx in
    let th : tool_handler =
      {
        info = { name; title; description };
        schema = None;
        handler = typed_handler;
      }
    in
    Hashtbl.replace t.tools name th;
    t.capabilities <-
      { t.capabilities with tools = Some { list_changed = None } }

  (* Main tool function *)
  let tool : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?args:(module Json_converter with type t = a) ->
      (a -> Context.t -> (Mcp.Request.Tools.Call.result, string) result) ->
      unit =
   fun t name ?title ?description ?args handler ->
    match args with
    | None ->
        tool_no_args t name ?title ?description
          (Obj.magic handler
            : unit ->
              Context.t ->
              (Mcp.Request.Tools.Call.result, string) result)
    | Some (module Args : Json_converter with type t = a) ->
        let schema = Args.schema () in
        let typed_handler json_opt ctx =
          let json = Option.value json_opt ~default:(`Assoc []) in
          match Args.of_yojson json with
          | Ok args -> handler args ctx
          | Error e -> Error ("Failed to parse arguments: " ^ e)
        in
        let th : tool_handler =
          {
            info = { name; title; description };
            schema = Some schema;
            handler = typed_handler;
          }
        in
        Hashtbl.replace t.tools name th;
        t.capabilities <-
          { t.capabilities with tools = Some { list_changed = None } }

  let resource t name ~uri ?description ?mime_type handler =
    let resource_handler =
      StaticResource
        { info = { name; title = None; description }; uri; mime_type; handler }
    in

    Hashtbl.replace t.resources name resource_handler;

    t.capabilities <-
      {
        t.capabilities with
        resources = Some { subscribe = None; list_changed = None };
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
        resources = Some { subscribe = None; list_changed = None };
      }

  (* Helper function for prompts with no arguments *)
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
      { t.capabilities with prompts = Some { list_changed = None } }

  (* Main prompt function *)
  let prompt : type a.
      t ->
      string ->
      ?title:string ->
      ?description:string ->
      ?args:(module Json_converter with type t = a) ->
      (a -> Context.t -> (Mcp.Request.Prompts.Get.result, string) result) ->
      unit =
   fun t name ?title ?description ?args handler ->
    match args with
    | None ->
        prompt_no_args t name ?title ?description
          (Obj.magic handler
            : unit ->
              Context.t ->
              (Mcp.Request.Prompts.Get.result, string) result)
    | Some (module Args : Json_converter with type t = a) ->
        let schema = Args.schema () in
        let typed_handler json_opt ctx =
          let json = Option.value json_opt ~default:(`Assoc []) in
          match Args.of_yojson json with
          | Ok args -> handler args ctx
          | Error e -> Error ("Failed to parse arguments: " ^ e)
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

  let parse_uri_template template uri =
    let rec extract_vars acc template =
      match String.index_opt template '{' with
      | None -> List.rev acc
      | Some start -> (
          match String.index_from_opt template start '}' with
          | None -> List.rev acc
          | Some end_ ->
              let var_name =
                String.sub template (start + 1) (end_ - start - 1)
              in
              let rest =
                String.sub template (end_ + 1)
                  (String.length template - end_ - 1)
              in
              extract_vars (var_name :: acc) rest)
    in

    let vars = extract_vars [] template in

    let regex_pattern =
      let escaped = String.split_on_char '{' template in
      let parts =
        List.mapi
          (fun i part ->
            if i = 0 then Str.quote part
            else
              match String.index_opt part '}' with
              | None -> Str.quote part
              | Some idx ->
                  let after =
                    String.sub part (idx + 1) (String.length part - idx - 1)
                  in
                  "\\([^/]+\\)" ^ Str.quote after)
          escaped
      in
      String.concat "" parts
    in

    try
      let regex = Str.regexp regex_pattern in
      if Str.string_match regex uri 0 then
        let values =
          List.mapi (fun i var -> (var, Str.matched_group (i + 1) uri)) vars
        in
        Some values
      else None
    with _ -> None

  let to_mcp_server t =
    let send_notification_ref = ref (fun _ -> ()) in

    let make_context req_id prog_token =
      { Context.req_id; prog_token; send_notif = !send_notification_ref }
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
              });
        on_tools_list =
          (fun _params ->
            let tools =
              Hashtbl.fold
                (fun _name (h : tool_handler) acc ->
                  {
                    Mcp.Types.Tool.name = h.info.name;
                    title = h.info.title;
                    description = h.info.description;
                    input_schema = Option.value ~default:(`Assoc []) h.schema;
                    output_schema = None;
                    annotations = None;
                  }
                  :: acc)
                t.tools []
            in
            Ok { tools; next_cursor = None });
        on_tools_call =
          (fun params ->
            match Hashtbl.find_opt t.tools params.name with
            | None -> Error ("Unknown tool: " ^ params.name)
            | Some h ->
                let ctx = make_context (String "tool-call") None in
                h.handler params.arguments ctx);
        on_resources_list =
          (fun _params ->
            let resources =
              Hashtbl.fold
                (fun _name handler acc ->
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
                      }
                      :: acc
                  | TemplateResource r -> (
                      match r.list_handler with
                      | None -> acc
                      | Some list_fn -> (
                          let ctx =
                            make_context (String "resource-list") None
                          in
                          match list_fn ctx with
                          | Ok result -> result.resources @ acc
                          | Error _ -> acc)))
                t.resources []
            in
            Ok { resources; next_cursor = None });
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
                      }
                      :: acc)
                t.resources []
            in
            Ok { resource_templates = templates; next_cursor = None });
        on_resources_read =
          (fun params ->
            let check_static uri =
              Hashtbl.fold
                (fun _name handler acc ->
                  match acc with
                  | Some _ -> acc
                  | None -> (
                      match handler with
                      | StaticResource r when r.uri = uri ->
                          let ctx =
                            make_context (String "resource-read") None
                          in
                          Some (r.handler uri ctx)
                      | _ -> None))
                t.resources None
            in

            let check_template uri =
              Hashtbl.fold
                (fun _name handler acc ->
                  match acc with
                  | Some _ -> acc
                  | None -> (
                      match handler with
                      | TemplateResource r -> (
                          match parse_uri_template r.template uri with
                          | Some vars ->
                              let ctx =
                                make_context (String "resource-read") None
                              in
                              Some (r.read_handler vars ctx)
                          | None -> None)
                      | _ -> None))
                t.resources None
            in

            match check_static params.uri with
            | Some result -> result
            | None -> (
                match check_template params.uri with
                | Some result -> result
                | None -> Error ("Resource not found: " ^ params.uri)));
        on_prompts_list =
          (fun _params ->
            let prompts =
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
                  }
                  :: acc)
                t.prompts []
            in
            Ok { prompts; next_cursor = None });
        on_prompts_get =
          (fun params ->
            match Hashtbl.find_opt t.prompts params.name with
            | None -> Error ("Unknown prompt: " ^ params.name)
            | Some h ->
                let ctx = make_context (String "prompt-get") None in
                let json_args =
                  match params.arguments with
                  | None -> None
                  | Some args ->
                      Some
                        (`Assoc (List.map (fun (k, v) -> (k, `String v)) args))
                in
                h.handler json_args ctx);
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
end

module Client = struct
  type t = {
    client_info : Types.ClientInfo.t;
    client_capabilities : Types.Capabilities.client;
  }

  let create ~client_info ~client_capabilities =
    { client_info; client_capabilities }

  let get_mcp_client t =
    Mcp.Client.create
      ~notification_handler:Mcp.Client.default_notification_handler
      ~client_info:t.client_info ~client_capabilities:t.client_capabilities ()

  let initialize t callback =
    let mcp_client = get_mcp_client t in
    Mcp.Client.initialize mcp_client
      ~protocol_version:Types.Protocol.latest_version (function
      | Ok result -> callback (Ok result)
      | Error e -> callback (Error e))

  let tools_list t callback =
    let params = { Mcp.Request.Tools.List.cursor = None } in
    let request : Mcp.Request.t = Mcp.Request.ToolsList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Tools.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let tools_call t ~name ~args ~args_to_yojson callback =
    let params =
      { Mcp.Request.Tools.Call.name; arguments = Some (args_to_yojson args) }
    in
    let request : Mcp.Request.t = Mcp.Request.ToolsCall params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Tools.Call.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let resources_list t callback =
    let params = { Mcp.Request.Resources.List.cursor = None } in
    let request : Mcp.Request.t = Mcp.Request.ResourcesList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Resources.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let resources_read t ~uri callback =
    let params = { Mcp.Request.Resources.Read.uri } in
    let request : Mcp.Request.t = Mcp.Request.ResourcesRead params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Resources.Read.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let prompts_list t callback =
    let params = { Mcp.Request.Prompts.List.cursor = None } in
    let request : Mcp.Request.t = Mcp.Request.PromptsList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Prompts.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let prompts_get t ~name ~args ~args_to_yojson callback =
    let args_json = args_to_yojson args in
    let arguments =
      match args_json with
      | `Assoc fields ->
          Some
            (List.map
               (fun (k, v) ->
                 match v with
                 | `String s -> (k, s)
                 | _ -> (k, Yojson.Safe.to_string v))
               fields)
      | _ -> None
    in
    let params = { Mcp.Request.Prompts.Get.name; arguments } in
    let request : Mcp.Request.t = Mcp.Request.PromptsGet params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Mcp.Request.Prompts.Get.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))
end
