open Mcp_types

module Initialized = struct
  type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
end

module Progress = struct
  type params = {
    progress_token : progress_token; [@key "progressToken"]
    progress : float;
    total : float option; [@default None]
  }
  [@@deriving yojson { strict = false }]
end

module Cancelled = struct
  type params = {
    request_id : request_id; [@key "requestId"]
    reason : string option; [@default None]
  }
  [@@deriving yojson { strict = false }]
end

module Resources = struct
  module Updated = struct
    type params = { uri : string } [@@deriving yojson { strict = false }]
  end

  module ListChanged = struct
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

module Prompts = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

module Tools = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

module Roots = struct
  module ListChanged = struct
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

module Message = struct
  type params = {
    level : LogLevel.t;
    logger : string option; [@default None]
    data : Yojson.Safe.t;
  }
  [@@deriving yojson { strict = false }]
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

let to_yojson = function
  | Initialized params -> Initialized.params_to_yojson params
  | Progress params -> Progress.params_to_yojson params
  | Cancelled params -> Cancelled.params_to_yojson params
  | ResourcesUpdated params -> Resources.Updated.params_to_yojson params
  | ResourcesListChanged params -> Resources.ListChanged.params_to_yojson params
  | PromptsListChanged params -> Prompts.ListChanged.params_to_yojson params
  | ToolsListChanged params -> Tools.ListChanged.params_to_yojson params
  | RootsListChanged params -> Roots.ListChanged.params_to_yojson params
  | Message params -> Message.params_to_yojson params

let of_jsonrpc (method_ : string) (params : Yojson.Safe.t option) :
    (t, string) result =
  let params = Option.value params ~default:`Null in
  match method_ with
  | "notifications/initialized" -> (
      match Initialized.params_of_yojson params with
      | Ok params -> Ok (Initialized params)
      | Error e -> Error e)
  | "notifications/progress" -> (
      match Progress.params_of_yojson params with
      | Ok params -> Ok (Progress params)
      | Error e -> Error e)
  | "notifications/cancelled" -> (
      match Cancelled.params_of_yojson params with
      | Ok params -> Ok (Cancelled params)
      | Error e -> Error e)
  | "notifications/resources/updated" -> (
      match Resources.Updated.params_of_yojson params with
      | Ok params -> Ok (ResourcesUpdated params)
      | Error e -> Error e)
  | "notifications/resources/list_changed" -> (
      match Resources.ListChanged.params_of_yojson params with
      | Ok params -> Ok (ResourcesListChanged params)
      | Error e -> Error e)
  | "notifications/prompts/list_changed" -> (
      match Prompts.ListChanged.params_of_yojson params with
      | Ok params -> Ok (PromptsListChanged params)
      | Error e -> Error e)
  | "notifications/tools/list_changed" -> (
      match Tools.ListChanged.params_of_yojson params with
      | Ok params -> Ok (ToolsListChanged params)
      | Error e -> Error e)
  | "notifications/roots/list_changed" -> (
      match Roots.ListChanged.params_of_yojson params with
      | Ok params -> Ok (RootsListChanged params)
      | Error e -> Error e)
  | "notifications/message" -> (
      match Message.params_of_yojson params with
      | Ok params -> Ok (Message params)
      | Error e -> Error e)
  | _ -> Error (Printf.sprintf "Unknown notification: %s" method_)
