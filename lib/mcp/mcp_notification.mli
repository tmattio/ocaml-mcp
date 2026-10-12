(** MCP notification types.

    This module defines all notification types in the Model Context Protocol.
    Notifications are one-way messages that don't expect responses, used for
    state changes, progress updates, and log messages. *)

open Mcp_types

(** Sent after successful initialization handshake. *)
module Initialized : sig
  type params = OnlyMetaParams.t

  val params_json : params Jsont.t
end

(** Progress updates for long-running operations. *)
module Progress : sig
  type params = {
    progress_token : progress_token;
    progress : float;
    total : float option;
  }

  val params_json : params Jsont.t
end

(** Request cancellation notification. *)
module Cancelled : sig
  type params = { request_id : request_id; reason : string option }

  val params_json : params Jsont.t
end

(** Resource change notifications. *)
module Resources : sig
  (** Specific resource content updated. *)
  module Updated : sig
    type params = { uri : string }

    val params_json : params Jsont.t
  end

  (** Available resources list changed. *)
  module ListChanged : sig
    type params = OnlyMetaParams.t

    val params_json : params Jsont.t
  end
end

(** Prompt list change notifications. *)
module Prompts : sig
  (** Available prompts list changed. *)
  module ListChanged : sig
    type params = OnlyMetaParams.t

    val params_json : params Jsont.t
  end
end

(** Tool list change notifications. *)
module Tools : sig
  (** Available tools list changed. *)
  module ListChanged : sig
    type params = OnlyMetaParams.t

    val params_json : params Jsont.t
  end
end

(** Root directory change notifications. *)
module Roots : sig
  (** Root directories list changed. *)
  module ListChanged : sig
    type params = OnlyMetaParams.t

    val params_json : params Jsont.t
  end
end

(** Log message from server. *)
module Message : sig
  type params = {
    level : LogLevel.t;
    logger : string option;
    data : Jsont.json;
  }

  val params_json : params Jsont.t
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
      (** Notification variants for all MCP notifications. *)

val method_name : t -> string
(** [method_name notification] returns JSON-RPC method name. *)

val to_json : t -> Jsont.json
(** [to_json notification] converts to JSON parameters. *)

val of_jsonrpc : string -> Jsont.json option -> (t, string) result
(** [of_jsonrpc method params] parses JSON-RPC into typed notification.

    @param method JSON-RPC method name
    @param params optional parameters
    @return Ok with typed notification or Error with description *)
