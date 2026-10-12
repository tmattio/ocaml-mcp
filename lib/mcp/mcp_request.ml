open Mcp_types

module Initialize = struct
  type params = {
    protocol_version : string;
    capabilities : Capabilities.client;
    client_info : ClientInfo.t;
  }

  let params_json : params Jsont.t =
    Jsont.Object.map (fun protocol_version capabilities client_info ->
        ({ protocol_version; capabilities; client_info } : params))
    |> Jsont.Object.mem "protocolVersion" Jsont.string ~enc:(fun (v : params) ->
        v.protocol_version)
    |> Jsont.Object.mem "capabilities" Capabilities.client_json
         ~enc:(fun (v : params) -> v.capabilities)
    |> Jsont.Object.mem "clientInfo" ClientInfo.json ~enc:(fun (v : params) ->
        v.client_info)
    |> Jsont.Object.finish |> Json_codec.last_object

  type result = {
    protocol_version : string;
    capabilities : Capabilities.server;
    server_info : ServerInfo.t;
    instructions : string option;
    meta : Jsont.json option;
  }

  let result_json : result Jsont.t =
    Jsont.Object.map
      (fun protocol_version capabilities server_info instructions meta ->
        ({ protocol_version; capabilities; server_info; instructions; meta }
          : result))
    |> Jsont.Object.mem "protocolVersion" Jsont.string ~enc:(fun (v : result) ->
        v.protocol_version)
    |> Jsont.Object.mem "capabilities" Capabilities.server_json
         ~enc:(fun (v : result) -> v.capabilities)
    |> Jsont.Object.mem "serverInfo" ServerInfo.json ~enc:(fun (v : result) ->
        v.server_info)
    |> Jsont.Object.mem "instructions" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
           v.instructions)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Resources = struct
  module List = struct
    type params = { cursor : cursor option; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun cursor meta -> ({ cursor; meta } : params))
      |> Jsont.Object.mem "cursor" (Jsont.option cursor_json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      resources : Resource.t list;
      next_cursor : cursor option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun resources next_cursor meta ->
          ({ resources; next_cursor; meta } : result))
      |> Jsont.Object.mem "resources" (Jsont.list Resource.json)
           ~enc:(fun (v : result) -> v.resources)
      |> Jsont.Object.mem "nextCursor" (Jsont.option cursor_json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.next_cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end

  module Read = struct
    type params = { uri : string; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun uri meta -> ({ uri; meta } : params))
      |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : params) -> v.uri)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      contents : Content.resource_contents list;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun contents meta -> ({ contents; meta } : result))
      |> Jsont.Object.mem "contents" (Jsont.list Content.resource_contents_json)
           ~enc:(fun (v : result) -> v.contents)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end

  module Subscribe = struct
    type params = { uri : string; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun uri meta -> ({ uri; meta } : params))
      |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : params) -> v.uri)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = unit

    let result_json : result Jsont.t = Jsont.null ()
  end

  module Unsubscribe = struct
    type params = { uri : string; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun uri meta -> ({ uri; meta } : params))
      |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : params) -> v.uri)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = unit

    let result_json : result Jsont.t = Jsont.null ()
  end

  module Templates = struct
    module List = struct
      type params = { cursor : cursor option; meta : Jsont.json option }

      let params_json : params Jsont.t =
        Jsont.Object.map (fun cursor meta -> ({ cursor; meta } : params))
        |> Jsont.Object.mem "cursor" (Jsont.option cursor_json) ~dec_absent:None
             ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.cursor)
        |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
             ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
        |> Jsont.Object.finish |> Json_codec.last_object

      type result = {
        resource_templates : Resource.template list;
        next_cursor : cursor option;
        meta : Jsont.json option;
      }

      let result_json : result Jsont.t =
        Jsont.Object.map (fun resource_templates next_cursor meta ->
            ({ resource_templates; next_cursor; meta } : result))
        |> Jsont.Object.mem "resourceTemplates"
             (Jsont.list Resource.template_json) ~enc:(fun (v : result) ->
               v.resource_templates)
        |> Jsont.Object.mem "nextCursor" (Jsont.option cursor_json)
             ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
               v.next_cursor)
        |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
             ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
        |> Jsont.Object.finish |> Json_codec.last_object
    end
  end
end

module Prompts = struct
  module List = struct
    type params = { cursor : cursor option; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun cursor meta -> ({ cursor; meta } : params))
      |> Jsont.Object.mem "cursor" (Jsont.option cursor_json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      prompts : Prompt.t list;
      next_cursor : cursor option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun prompts next_cursor meta ->
          ({ prompts; next_cursor; meta } : result))
      |> Jsont.Object.mem "prompts" (Jsont.list Prompt.json)
           ~enc:(fun (v : result) -> v.prompts)
      |> Jsont.Object.mem "nextCursor" (Jsont.option cursor_json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.next_cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end

  module Get = struct
    type params = {
      name : string;
      arguments : (string * string) list option;
      meta : Jsont.json option;
    }

    let params_json : params Jsont.t =
      let arguments_json =
        Jsont.map Jsont.json
          ~dec:(fun value ->
            match
              Json_codec.decode (Json_codec.assoc_json Jsont.string) value
            with
            | Ok args -> Some args
            | Error _ -> None)
          ~enc:(function
            | None -> Jsont.Json.null ()
            | Some args ->
                Json_codec.encode (Json_codec.assoc_json Jsont.string) args)
      in
      Jsont.Object.map (fun name arguments meta -> { name; arguments; meta })
      |> Jsont.Object.mem "name" Jsont.string ~enc:(fun v -> v.name)
      |> Jsont.Object.mem "arguments" arguments_json ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun v -> v.arguments)
      |> Jsont.Object.opt_mem "_meta" Jsont.json ~enc:(fun v -> v.meta)
      |> Jsont.Object.finish |> Json_codec.first_object

    type result = {
      description : string option;
      messages : Prompt.message list;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun description messages meta ->
          ({ description; messages; meta } : result))
      |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.description)
      |> Jsont.Object.mem "messages" (Jsont.list Prompt.message_json)
           ~enc:(fun (v : result) -> v.messages)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end
end

module Tools = struct
  module List = struct
    type params = { cursor : cursor option; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun cursor meta -> ({ cursor; meta } : params))
      |> Jsont.Object.mem "cursor" (Jsont.option cursor_json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      tools : Tool.t list;
      next_cursor : cursor option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun tools next_cursor meta ->
          ({ tools; next_cursor; meta } : result))
      |> Jsont.Object.mem "tools" (Jsont.list Tool.json)
           ~enc:(fun (v : result) -> v.tools)
      |> Jsont.Object.mem "nextCursor" (Jsont.option cursor_json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.next_cursor)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end

  module Call = struct
    type params = {
      name : string;
      arguments : Jsont.json option;
      meta : Jsont.json option;
    }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun name arguments meta ->
          ({ name; arguments; meta } : params))
      |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : params) -> v.name)
      |> Jsont.Object.mem "arguments" (Jsont.option Jsont.json)
           ~enc:(fun (v : params) -> v.arguments)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      content : Content.t list;
      is_error : bool option;
      structured_content : Jsont.json option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun content is_error structured_content meta ->
          ({ content; is_error; structured_content; meta } : result))
      |> Jsont.Object.mem "content" (Jsont.list Content.json)
           ~enc:(fun (v : result) -> v.content)
      |> Jsont.Object.mem "isError" (Jsont.option Jsont.bool) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.is_error)
      |> Jsont.Object.mem "structuredContent" (Jsont.option Jsont.json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.structured_content)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end
end

module Sampling = struct
  module CreateMessage = struct
    type params = {
      messages : SamplingMessage.t list;
      model_preferences : ModelPreferences.t option;
      system_prompt : string option;
      include_context : string option;
      temperature : float option;
      max_tokens : int option;
      stop_sequences : string list option;
      metadata : Jsont.json option;
    }

    let params_json : params Jsont.t =
      Jsont.Object.map
        (fun
          messages
          model_preferences
          system_prompt
          include_context
          temperature
          max_tokens
          stop_sequences
          metadata
        ->
          ({
             messages;
             model_preferences;
             system_prompt;
             include_context;
             temperature;
             max_tokens;
             stop_sequences;
             metadata;
           }
            : params))
      |> Jsont.Object.mem "messages" (Jsont.list SamplingMessage.json)
           ~enc:(fun (v : params) -> v.messages)
      |> Jsont.Object.mem "modelPreferences"
           (Jsont.option ModelPreferences.json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
             v.model_preferences)
      |> Jsont.Object.mem "systemPrompt" (Jsont.option Jsont.string)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
             v.system_prompt)
      |> Jsont.Object.mem "includeContext" (Jsont.option Jsont.string)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
             v.include_context)
      |> Jsont.Object.mem "temperature" (Jsont.option Json_codec.number_json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
             v.temperature)
      |> Jsont.Object.mem "maxTokens" (Jsont.option Json_codec.integer_json)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
             v.max_tokens)
      |> Jsont.Object.mem "stopSequences"
           (Jsont.option (Jsont.list Jsont.string))
           ~dec_absent:None ~enc_omit:Option.is_none
           ~enc:(fun (v : params) -> v.stop_sequences)
      |> Jsont.Object.mem "metadata" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.metadata)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = {
      role : string;
      content : Content.t;
      model : string;
      stop_reason : string option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun role content model stop_reason meta ->
          ({ role; content; model; stop_reason; meta } : result))
      |> Jsont.Object.mem "role" Jsont.string ~enc:(fun (v : result) -> v.role)
      |> Jsont.Object.mem "content" Content.json ~enc:(fun (v : result) ->
          v.content)
      |> Jsont.Object.mem "model" Jsont.string ~enc:(fun (v : result) ->
          v.model)
      |> Jsont.Object.mem "stopReason" (Jsont.option Jsont.string)
           ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : result) ->
             v.stop_reason)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end
end

module Elicitation = struct
  module Create = struct
    type params = {
      message : string;
      requested_schema : ElicitationSchema.t;
      meta : Jsont.json option;
    }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun message requested_schema meta ->
          { message; requested_schema; meta })
      |> Jsont.Object.mem "message" Jsont.string ~enc:(fun v -> v.message)
      |> Jsont.Object.mem "requestedSchema" ElicitationSchema.json
           ~enc:(fun v -> v.requested_schema)
      |> Jsont.Object.opt_mem "_meta" Jsont.json ~enc:(fun v -> v.meta)
      |> Jsont.Object.finish |> Json_codec.first_object

    type result = {
      action : string;
      content : (string * Jsont.json) list option;
      meta : Jsont.json option;
    }

    let result_json : result Jsont.t =
      let content_json =
        Jsont.map Jsont.json
          ~dec:(fun value ->
            match
              Json_codec.decode (Json_codec.assoc_json Jsont.json) value
            with
            | Ok content -> Some content
            | Error _ -> None)
          ~enc:(function
            | None -> Jsont.Json.null ()
            | Some content ->
                Json_codec.encode (Json_codec.assoc_json Jsont.json) content)
      in
      Jsont.Object.map (fun action content meta -> { action; content; meta })
      |> Jsont.Object.mem "action" Jsont.string ~enc:(fun v -> v.action)
      |> Jsont.Object.mem "content" content_json ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun v -> v.content)
      |> Jsont.Object.mem "_meta" (Jsont.some Jsont.json) ~dec_absent:None
           ~enc_omit:(fun _ -> true)
           ~enc:(fun v -> v.meta)
      |> Jsont.Object.finish |> Json_codec.first_object
  end
end

module Logging = struct
  module SetLevel = struct
    type params = { level : LogLevel.t; meta : Jsont.json option }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun level meta -> ({ level; meta } : params))
      |> Jsont.Object.mem "level" LogLevel.json ~enc:(fun (v : params) ->
          v.level)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = OnlyMetaParams.t

    let result_json : result Jsont.t = OnlyMetaParams.json
  end
end

module Completion = struct
  module Complete = struct
    type params = {
      ref_ : CompletionReference.t;
      argument : CompletionArgument.t;
      meta : Jsont.json option;
    }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun ref_ argument meta ->
          ({ ref_; argument; meta } : params))
      |> Jsont.Object.mem "ref" CompletionReference.json
           ~enc:(fun (v : params) -> v.ref_)
      |> Jsont.Object.mem "argument" CompletionArgument.json
           ~enc:(fun (v : params) -> v.argument)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : params) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object

    type result = { completion : Completion.t; meta : Jsont.json option }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun completion meta -> ({ completion; meta } : result))
      |> Jsont.Object.mem "completion" Completion.json ~enc:(fun (v : result) ->
          v.completion)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end
end

module Roots = struct
  module List = struct
    type params = OnlyMetaParams.t

    let params_json : params Jsont.t = OnlyMetaParams.json

    type result = { roots : Root.t list; meta : Jsont.json option }

    let result_json : result Jsont.t =
      Jsont.Object.map (fun roots meta -> ({ roots; meta } : result))
      |> Jsont.Object.mem "roots" (Jsont.list Root.json)
           ~enc:(fun (v : result) -> v.roots)
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun (v : result) -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
  end
end

module Ping = struct
  type params = OnlyMetaParams.t

  let params_json : params Jsont.t = OnlyMetaParams.json

  type result = OnlyMetaParams.t

  let result_json : result Jsont.t = OnlyMetaParams.json
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

let params_to_json = function
  | Initialize params -> Json_codec.encode Initialize.params_json params
  | ResourcesList params -> Json_codec.encode Resources.List.params_json params
  | ResourcesRead params -> Json_codec.encode Resources.Read.params_json params
  | ResourcesSubscribe params ->
      Json_codec.encode Resources.Subscribe.params_json params
  | ResourcesUnsubscribe params ->
      Json_codec.encode Resources.Unsubscribe.params_json params
  | ResourcesTemplatesList params ->
      Json_codec.encode Resources.Templates.List.params_json params
  | PromptsList params -> Json_codec.encode Prompts.List.params_json params
  | PromptsGet params -> Json_codec.encode Prompts.Get.params_json params
  | ToolsList params -> Json_codec.encode Tools.List.params_json params
  | ToolsCall params -> Json_codec.encode Tools.Call.params_json params
  | SamplingCreateMessage params ->
      Json_codec.encode Sampling.CreateMessage.params_json params
  | ElicitationCreate params ->
      Json_codec.encode Elicitation.Create.params_json params
  | LoggingSetLevel params ->
      Json_codec.encode Logging.SetLevel.params_json params
  | CompletionComplete params ->
      Json_codec.encode Completion.Complete.params_json params
  | RootsList params -> Json_codec.encode Roots.List.params_json params
  | Ping params -> Json_codec.encode Ping.params_json params

let of_jsonrpc (method_ : string) (params : Jsont.json option) :
    (t, string) result =
  let params = Option.value params ~default:(Jsont.Json.object' []) in
  match method_ with
  | "initialize" -> (
      match Json_codec.decode Initialize.params_json params with
      | Ok params -> Ok (Initialize params)
      | Error e -> Error e)
  | "resources/list" -> (
      match Json_codec.decode Resources.List.params_json params with
      | Ok params -> Ok (ResourcesList params)
      | Error e -> Error e)
  | "resources/read" -> (
      match Json_codec.decode Resources.Read.params_json params with
      | Ok params -> Ok (ResourcesRead params)
      | Error e -> Error e)
  | "resources/subscribe" -> (
      match Json_codec.decode Resources.Subscribe.params_json params with
      | Ok params -> Ok (ResourcesSubscribe params)
      | Error e -> Error e)
  | "resources/unsubscribe" -> (
      match Json_codec.decode Resources.Unsubscribe.params_json params with
      | Ok params -> Ok (ResourcesUnsubscribe params)
      | Error e -> Error e)
  | "resources/templates/list" -> (
      match Json_codec.decode Resources.Templates.List.params_json params with
      | Ok params -> Ok (ResourcesTemplatesList params)
      | Error e -> Error e)
  | "prompts/list" -> (
      match Json_codec.decode Prompts.List.params_json params with
      | Ok params -> Ok (PromptsList params)
      | Error e -> Error e)
  | "prompts/get" -> (
      match Json_codec.decode Prompts.Get.params_json params with
      | Ok params -> Ok (PromptsGet params)
      | Error e -> Error e)
  | "tools/list" -> (
      match Json_codec.decode Tools.List.params_json params with
      | Ok params -> Ok (ToolsList params)
      | Error e -> Error e)
  | "tools/call" -> (
      match Json_codec.decode Tools.Call.params_json params with
      | Ok params -> Ok (ToolsCall params)
      | Error e -> Error e)
  | "sampling/createMessage" -> (
      match Json_codec.decode Sampling.CreateMessage.params_json params with
      | Ok params -> Ok (SamplingCreateMessage params)
      | Error e -> Error e)
  | "elicitation/create" -> (
      match Json_codec.decode Elicitation.Create.params_json params with
      | Ok params -> Ok (ElicitationCreate params)
      | Error e -> Error e)
  | "logging/setLevel" -> (
      match Json_codec.decode Logging.SetLevel.params_json params with
      | Ok params -> Ok (LoggingSetLevel params)
      | Error e -> Error e)
  | "completion/complete" -> (
      match Json_codec.decode Completion.Complete.params_json params with
      | Ok params -> Ok (CompletionComplete params)
      | Error e -> Error e)
  | "roots/list" -> (
      match Json_codec.decode Roots.List.params_json params with
      | Ok params -> Ok (RootsList params)
      | Error e -> Error e)
  | "ping" -> (
      match Json_codec.decode Ping.params_json params with
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

let response_to_json = function
  | Initialize result -> Json_codec.encode Initialize.result_json result
  | ResourcesList result -> Json_codec.encode Resources.List.result_json result
  | ResourcesRead result -> Json_codec.encode Resources.Read.result_json result
  | ResourcesSubscribe result ->
      Json_codec.encode Resources.Subscribe.result_json result
  | ResourcesUnsubscribe result ->
      Json_codec.encode Resources.Unsubscribe.result_json result
  | ResourcesTemplatesList result ->
      Json_codec.encode Resources.Templates.List.result_json result
  | PromptsList result -> Json_codec.encode Prompts.List.result_json result
  | PromptsGet result -> Json_codec.encode Prompts.Get.result_json result
  | ToolsList result -> Json_codec.encode Tools.List.result_json result
  | ToolsCall result -> Json_codec.encode Tools.Call.result_json result
  | SamplingCreateMessage result ->
      Json_codec.encode Sampling.CreateMessage.result_json result
  | ElicitationCreate result ->
      Json_codec.encode Elicitation.Create.result_json result
  | LoggingSetLevel result ->
      Json_codec.encode Logging.SetLevel.result_json result
  | CompletionComplete result ->
      Json_codec.encode Completion.Complete.result_json result
  | RootsList result -> Json_codec.encode Roots.List.result_json result
  | Ping result -> Json_codec.encode Ping.result_json result
