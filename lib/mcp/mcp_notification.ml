open Mcp_types

module Initialized = struct
  type params = OnlyMetaParams.t

  let params_json : params Jsont.t = OnlyMetaParams.json
end

module Progress = struct
  type params = {
    progress_token : progress_token;
    progress : float;
    total : float option;
  }

  let params_json : params Jsont.t =
    Jsont.Object.map (fun progress_token progress total ->
        ({ progress_token; progress; total } : params))
    |> Jsont.Object.mem "progressToken" progress_token_json
         ~enc:(fun (v : params) -> v.progress_token)
    |> Jsont.Object.mem "progress" Json_codec.number_json
         ~enc:(fun (v : params) -> v.progress)
    |> Jsont.Object.mem "total" (Jsont.option Json_codec.number_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
           v.total)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Cancelled = struct
  type params = { request_id : request_id; reason : string option }

  let params_json : params Jsont.t =
    Jsont.Object.map (fun request_id reason ->
        ({ request_id; reason } : params))
    |> Jsont.Object.mem "requestId" request_id_json ~enc:(fun (v : params) ->
        v.request_id)
    |> Jsont.Object.mem "reason" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
           v.reason)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Resources = struct
  module Updated = struct
    type params = { uri : string }

    let params_json : params Jsont.t =
      Jsont.Object.map (fun uri -> ({ uri } : params))
      |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : params) -> v.uri)
      |> Jsont.Object.finish |> Json_codec.last_object
  end

  module ListChanged = struct
    type params = OnlyMetaParams.t

    let params_json : params Jsont.t = OnlyMetaParams.json
  end
end

module Prompts = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t

    let params_json : params Jsont.t = OnlyMetaParams.json
  end
end

module Tools = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t

    let params_json : params Jsont.t = OnlyMetaParams.json
  end
end

module Roots = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t

    let params_json : params Jsont.t = OnlyMetaParams.json
  end
end

module Message = struct
  type params = {
    level : LogLevel.t;
    logger : string option;
    data : Jsont.json;
  }

  let params_json : params Jsont.t =
    Jsont.Object.map (fun level logger data ->
        ({ level; logger; data } : params))
    |> Jsont.Object.mem "level" LogLevel.json ~enc:(fun (v : params) -> v.level)
    |> Jsont.Object.mem "logger" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : params) ->
           v.logger)
    |> Jsont.Object.mem "data" Jsont.json ~enc:(fun (v : params) -> v.data)
    |> Jsont.Object.finish |> Json_codec.last_object
end

type t =
  | Initialized of Initialized.params
  | Progress of Progress.params
  | Cancelled of Cancelled.params
  | ResourcesUpdated of Resources.Updated.params
  | ResourcesListChanged of Resources.ListChanged.params
  | PromptsListChanged of Prompts.ListChanged.params
  | ToolsListChanged of Tools.ListChanged.params
  | RootsListChanged of Roots.ListChanged.params
  | Message of Message.params

let method_name = function
  | Initialized _ -> "notifications/initialized"
  | Progress _ -> "notifications/progress"
  | Cancelled _ -> "notifications/cancelled"
  | ResourcesUpdated _ -> "notifications/resources/updated"
  | ResourcesListChanged _ -> "notifications/resources/list_changed"
  | PromptsListChanged _ -> "notifications/prompts/list_changed"
  | ToolsListChanged _ -> "notifications/tools/list_changed"
  | RootsListChanged _ -> "notifications/roots/list_changed"
  | Message _ -> "notifications/message"

let to_json = function
  | Initialized params -> Json_codec.encode Initialized.params_json params
  | Progress params -> Json_codec.encode Progress.params_json params
  | Cancelled params -> Json_codec.encode Cancelled.params_json params
  | ResourcesUpdated params ->
      Json_codec.encode Resources.Updated.params_json params
  | ResourcesListChanged params ->
      Json_codec.encode Resources.ListChanged.params_json params
  | PromptsListChanged params ->
      Json_codec.encode Prompts.ListChanged.params_json params
  | ToolsListChanged params ->
      Json_codec.encode Tools.ListChanged.params_json params
  | RootsListChanged params ->
      Json_codec.encode Roots.ListChanged.params_json params
  | Message params -> Json_codec.encode Message.params_json params

let of_jsonrpc (method_ : string) (params : Jsont.json option) :
    (t, string) result =
  let params = Option.value params ~default:(Jsont.Json.null ()) in
  match method_ with
  | "notifications/initialized" -> (
      match Json_codec.decode Initialized.params_json params with
      | Ok params -> Ok (Initialized params)
      | Error e -> Error e)
  | "notifications/progress" -> (
      match Json_codec.decode Progress.params_json params with
      | Ok params -> Ok (Progress params)
      | Error e -> Error e)
  | "notifications/cancelled" -> (
      match Json_codec.decode Cancelled.params_json params with
      | Ok params -> Ok (Cancelled params)
      | Error e -> Error e)
  | "notifications/resources/updated" -> (
      match Json_codec.decode Resources.Updated.params_json params with
      | Ok params -> Ok (ResourcesUpdated params)
      | Error e -> Error e)
  | "notifications/resources/list_changed" -> (
      match Json_codec.decode Resources.ListChanged.params_json params with
      | Ok params -> Ok (ResourcesListChanged params)
      | Error e -> Error e)
  | "notifications/prompts/list_changed" -> (
      match Json_codec.decode Prompts.ListChanged.params_json params with
      | Ok params -> Ok (PromptsListChanged params)
      | Error e -> Error e)
  | "notifications/tools/list_changed" -> (
      match Json_codec.decode Tools.ListChanged.params_json params with
      | Ok params -> Ok (ToolsListChanged params)
      | Error e -> Error e)
  | "notifications/roots/list_changed" -> (
      match Json_codec.decode Roots.ListChanged.params_json params with
      | Ok params -> Ok (RootsListChanged params)
      | Error e -> Error e)
  | "notifications/message" -> (
      match Json_codec.decode Message.params_json params with
      | Ok params -> Ok (Message params)
      | Error e -> Error e)
  | _ -> Error (Printf.sprintf "Unknown notification: %s" method_)
