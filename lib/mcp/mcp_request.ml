open Mcp_types

module Initialize = struct
  type params = {
    protocol_version : string; [@key "protocolVersion"]
    capabilities : Capabilities.client;
    client_info : ClientInfo.t; [@key "clientInfo"]
  }
  [@@deriving yojson { strict = false }]

  type result = {
    protocol_version : string; [@key "protocolVersion"]
    capabilities : Capabilities.server;
    server_info : ServerInfo.t; [@key "serverInfo"]
    instructions : string option; [@default None]
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
end

module Resources = struct
  module List = struct
    type params = {
      cursor : cursor option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      resources : Resource.t list;
      next_cursor : cursor option; [@default None] [@key "nextCursor"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Read = struct
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      contents : Content.resource_contents list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Subscribe = struct
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = unit [@@deriving yojson { strict = false }]
  end

  module Unsubscribe = struct
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = unit [@@deriving yojson { strict = false }]
  end

  module Templates = struct
    module List = struct
      type params = {
        cursor : cursor option; [@default None]
        meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
      }
      [@@deriving yojson { strict = false }]

      type result = {
        resource_templates : Resource.template list; [@key "resourceTemplates"]
        next_cursor : cursor option; [@default None] [@key "nextCursor"]
        meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
      }
      [@@deriving yojson { strict = false }]
    end
  end
end

module Prompts = struct
  module List = struct
    type params = {
      cursor : cursor option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      prompts : Prompt.t list;
      next_cursor : cursor option; [@default None] [@key "nextCursor"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Get = struct
    type params = {
      name : string;
      arguments : (string * string) list option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    let params_to_yojson params =
      let fields = [ ("name", `String params.name) ] in
      let fields =
        match params.arguments with
        | None -> fields
        | Some args ->
            ( "arguments",
              `Assoc (Stdlib.List.map (fun (k, v) -> (k, `String v)) args) )
            :: fields
      in
      let fields =
        match params.meta with
        | None -> fields
        | Some meta -> ("_meta", meta) :: fields
      in
      `Assoc fields

    let params_of_yojson = function
      | `Assoc fields -> (
          match Stdlib.List.assoc_opt "name" fields with
          | Some (`String name) ->
              let arguments =
                match Stdlib.List.assoc_opt "arguments" fields with
                | Some (`Assoc args) -> (
                    let parse_args =
                      Stdlib.List.fold_left
                        (fun acc (k, v) ->
                          match acc with
                          | Error _ -> acc
                          | Ok args -> (
                              match v with
                              | `String s -> Ok ((k, s) :: args)
                              | _ -> Error "argument values must be strings"))
                        (Ok []) args
                    in
                    match parse_args with
                    | Ok args -> Some (Stdlib.List.rev args)
                    | Error _ -> None)
                | _ -> None
              in
              let meta = Stdlib.List.assoc_opt "_meta" fields in
              Ok { name; arguments; meta }
          | _ -> Error "Invalid prompts/get params")
      | _ -> Error "prompts/get params must be an object"

    type result = {
      description : string option; [@default None]
      messages : Prompt.message list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

module Tools = struct
  module List = struct
    type params = {
      cursor : cursor option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      tools : Tool.t list;
      next_cursor : cursor option; [@default None] [@key "nextCursor"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Call = struct
    type params = {
      name : string;
      arguments : Yojson.Safe.t option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      content : Content.t list;
      is_error : bool option; [@default None] [@key "isError"]
      structured_content : Yojson.Safe.t option;
          [@default None] [@key "structuredContent"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

module Sampling = struct
  module CreateMessage = struct
    type params = {
      messages : SamplingMessage.t list;
      model_preferences : ModelPreferences.t option;
          [@default None] [@key "modelPreferences"]
      system_prompt : string option; [@default None] [@key "systemPrompt"]
      include_context : string option; [@default None] [@key "includeContext"]
      temperature : float option; [@default None]
      max_tokens : int option; [@default None] [@key "maxTokens"]
      stop_sequences : string list option;
          [@default None] [@key "stopSequences"]
      metadata : Yojson.Safe.t option; [@default None]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      role : string;
      content : Content.t;
      model : string;
      stop_reason : string option; [@default None] [@key "stopReason"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

module Elicitation = struct
  module Create = struct
    type params = {
      message : string;
      requested_schema : ElicitationSchema.t; [@key "requestedSchema"]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    let params_to_yojson params =
      let fields =
        [
          ("message", `String params.message);
          ( "requestedSchema",
            ElicitationSchema.to_yojson params.requested_schema );
        ]
      in
      let fields =
        match params.meta with
        | None -> fields
        | Some meta -> ("_meta", meta) :: fields
      in
      `Assoc fields

    let params_of_yojson = function
      | `Assoc fields -> (
          match
            ( Stdlib.List.assoc_opt "message" fields,
              Stdlib.List.assoc_opt "requestedSchema" fields )
          with
          | Some (`String message), Some schema_json -> (
              match ElicitationSchema.of_yojson schema_json with
              | Ok requested_schema ->
                  let meta = Stdlib.List.assoc_opt "_meta" fields in
                  Ok { message; requested_schema; meta }
              | Error e -> Error ("Invalid requestedSchema: " ^ e))
          | _ -> Error "Invalid elicitation params")
      | _ -> Error "Elicitation params must be an object"

    type result = {
      action : string;
      content : (string * Yojson.Safe.t) list option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    let result_to_yojson result =
      let fields = [ ("action", `String result.action) ] in
      let fields =
        match result.content with
        | None -> fields
        | Some content -> ("content", `Assoc content) :: fields
      in
      `Assoc fields

    let result_of_yojson = function
      | `Assoc fields -> (
          match Stdlib.List.assoc_opt "action" fields with
          | Some (`String action) ->
              let content =
                match Stdlib.List.assoc_opt "content" fields with
                | Some (`Assoc content) -> Some content
                | _ -> None
              in
              let meta =
                match Stdlib.List.assoc_opt "_meta" fields with
                | Some meta -> Some meta
                | None -> None
              in
              Ok { action; content; meta }
          | _ -> Error "Invalid elicitation result")
      | _ -> Error "Elicitation result must be an object"
  end
end

module Logging = struct
  module SetLevel = struct
    type params = {
      level : LogLevel.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

module Completion = struct
  module Complete = struct
    type params = {
      ref_ : CompletionReference.t; [@key "ref"]
      argument : CompletionArgument.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      completion : Completion.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

module Roots = struct
  module List = struct
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]

    type result = {
      roots : Root.t list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

module Ping = struct
  type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  type result = unit

  let result_to_yojson () = `Assoc []
  let result_of_yojson _ = Ok ()
end

type t =
  | Initialize of Initialize.params
  | ResourcesList of Resources.List.params
  | ResourcesRead of Resources.Read.params
  | ResourcesSubscribe of Resources.Subscribe.params
  | ResourcesUnsubscribe of Resources.Unsubscribe.params
  | ResourcesTemplatesList of Resources.Templates.List.params
  | PromptsList of Prompts.List.params
  | PromptsGet of Prompts.Get.params
  | ToolsList of Tools.List.params
  | ToolsCall of Tools.Call.params
  | SamplingCreateMessage of Sampling.CreateMessage.params
  | ElicitationCreate of Elicitation.Create.params
  | LoggingSetLevel of Logging.SetLevel.params
  | CompletionComplete of Completion.Complete.params
  | RootsList of Roots.List.params
  | Ping of Ping.params

let method_name = function
  | Initialize _ -> "initialize"
  | ResourcesList _ -> "resources/list"
  | ResourcesRead _ -> "resources/read"
  | ResourcesSubscribe _ -> "resources/subscribe"
  | ResourcesUnsubscribe _ -> "resources/unsubscribe"
  | ResourcesTemplatesList _ -> "resources/templates/list"
  | PromptsList _ -> "prompts/list"
  | PromptsGet _ -> "prompts/get"
  | ToolsList _ -> "tools/list"
  | ToolsCall _ -> "tools/call"
  | SamplingCreateMessage _ -> "sampling/createMessage"
  | ElicitationCreate _ -> "elicitation/create"
  | LoggingSetLevel _ -> "logging/setLevel"
  | CompletionComplete _ -> "completion/complete"
  | RootsList _ -> "roots/list"
  | Ping _ -> "ping"

let params_to_yojson = function
  | Initialize params -> Initialize.params_to_yojson params
  | ResourcesList params -> Resources.List.params_to_yojson params
  | ResourcesRead params -> Resources.Read.params_to_yojson params
  | ResourcesSubscribe params -> Resources.Subscribe.params_to_yojson params
  | ResourcesUnsubscribe params -> Resources.Unsubscribe.params_to_yojson params
  | ResourcesTemplatesList params ->
      Resources.Templates.List.params_to_yojson params
  | PromptsList params -> Prompts.List.params_to_yojson params
  | PromptsGet params -> Prompts.Get.params_to_yojson params
  | ToolsList params -> Tools.List.params_to_yojson params
  | ToolsCall params -> Tools.Call.params_to_yojson params
  | SamplingCreateMessage params ->
      Sampling.CreateMessage.params_to_yojson params
  | ElicitationCreate params -> Elicitation.Create.params_to_yojson params
  | LoggingSetLevel params -> Logging.SetLevel.params_to_yojson params
  | CompletionComplete params -> Completion.Complete.params_to_yojson params
  | RootsList params -> Roots.List.params_to_yojson params
  | Ping params -> Ping.params_to_yojson params

let of_jsonrpc (method_ : string) (params : Yojson.Safe.t option) :
    (t, string) result =
  let params = Option.value params ~default:(`Assoc []) in
  match method_ with
  | "initialize" -> (
      match Initialize.params_of_yojson params with
      | Ok params -> Ok (Initialize params)
      | Error e -> Error e)
  | "resources/list" -> (
      match Resources.List.params_of_yojson params with
      | Ok params -> Ok (ResourcesList params)
      | Error e -> Error e)
  | "resources/read" -> (
      match Resources.Read.params_of_yojson params with
      | Ok params -> Ok (ResourcesRead params)
      | Error e -> Error e)
  | "resources/subscribe" -> (
      match Resources.Subscribe.params_of_yojson params with
      | Ok params -> Ok (ResourcesSubscribe params)
      | Error e -> Error e)
  | "resources/unsubscribe" -> (
      match Resources.Unsubscribe.params_of_yojson params with
      | Ok params -> Ok (ResourcesUnsubscribe params)
      | Error e -> Error e)
  | "resources/templates/list" -> (
      match Resources.Templates.List.params_of_yojson params with
      | Ok params -> Ok (ResourcesTemplatesList params)
      | Error e -> Error e)
  | "prompts/list" -> (
      match Prompts.List.params_of_yojson params with
      | Ok params -> Ok (PromptsList params)
      | Error e -> Error e)
  | "prompts/get" -> (
      match Prompts.Get.params_of_yojson params with
      | Ok params -> Ok (PromptsGet params)
      | Error e -> Error e)
  | "tools/list" -> (
      match Tools.List.params_of_yojson params with
      | Ok params -> Ok (ToolsList params)
      | Error e -> Error e)
  | "tools/call" -> (
      match Tools.Call.params_of_yojson params with
      | Ok params -> Ok (ToolsCall params)
      | Error e -> Error e)
  | "sampling/createMessage" -> (
      match Sampling.CreateMessage.params_of_yojson params with
      | Ok params -> Ok (SamplingCreateMessage params)
      | Error e -> Error e)
  | "elicitation/create" -> (
      match Elicitation.Create.params_of_yojson params with
      | Ok params -> Ok (ElicitationCreate params)
      | Error e -> Error e)
  | "logging/setLevel" -> (
      match Logging.SetLevel.params_of_yojson params with
      | Ok params -> Ok (LoggingSetLevel params)
      | Error e -> Error e)
  | "completion/complete" -> (
      match Completion.Complete.params_of_yojson params with
      | Ok params -> Ok (CompletionComplete params)
      | Error e -> Error e)
  | "roots/list" -> (
      match Roots.List.params_of_yojson params with
      | Ok params -> Ok (RootsList params)
      | Error e -> Error e)
  | "ping" -> (
      match Ping.params_of_yojson params with
      | Ok params -> Ok (Ping params)
      | Error e -> Error e)
  | _ -> Error (Printf.sprintf "Unknown method: %s" method_)

type response =
  | Initialize of Initialize.result
  | ResourcesList of Resources.List.result
  | ResourcesRead of Resources.Read.result
  | ResourcesSubscribe of Resources.Subscribe.result
  | ResourcesUnsubscribe of Resources.Unsubscribe.result
  | ResourcesTemplatesList of Resources.Templates.List.result
  | PromptsList of Prompts.List.result
  | PromptsGet of Prompts.Get.result
  | ToolsList of Tools.List.result
  | ToolsCall of Tools.Call.result
  | SamplingCreateMessage of Sampling.CreateMessage.result
  | ElicitationCreate of Elicitation.Create.result
  | LoggingSetLevel of Logging.SetLevel.result
  | CompletionComplete of Completion.Complete.result
  | RootsList of Roots.List.result
  | Ping of Ping.result

let response_to_yojson = function
  | Initialize result -> Initialize.result_to_yojson result
  | ResourcesList result -> Resources.List.result_to_yojson result
  | ResourcesRead result -> Resources.Read.result_to_yojson result
  | ResourcesSubscribe result -> Resources.Subscribe.result_to_yojson result
  | ResourcesUnsubscribe result -> Resources.Unsubscribe.result_to_yojson result
  | ResourcesTemplatesList result ->
      Resources.Templates.List.result_to_yojson result
  | PromptsList result -> Prompts.List.result_to_yojson result
  | PromptsGet result -> Prompts.Get.result_to_yojson result
  | ToolsList result -> Tools.List.result_to_yojson result
  | ToolsCall result -> Tools.Call.result_to_yojson result
  | SamplingCreateMessage result ->
      Sampling.CreateMessage.result_to_yojson result
  | ElicitationCreate result -> Elicitation.Create.result_to_yojson result
  | LoggingSetLevel result -> Logging.SetLevel.result_to_yojson result
  | CompletionComplete result -> Completion.Complete.result_to_yojson result
  | RootsList result -> Roots.List.result_to_yojson result
  | Ping result -> Ping.result_to_yojson result
