(** MCP notification types.

    This module defines all notification types in the Model Context Protocol.
    Notifications are one-way messages that don't expect responses, used for
    state changes, progress updates, and log messages. *)

open Mcp_types

(** Sent after successful initialization handshake. *)
module Initialized : sig
  type params = unit [@@deriving yojson]
end

(** Progress updates for long-running operations. *)
module Progress : sig
  type params = {
    progress_token : progress_token;
    progress : float;
    total : float option;
  }
  [@@deriving yojson]
end

(** Request cancellation notification. *)
module Cancelled : sig
  type params = { request_id : request_id; reason : string option }
  [@@deriving yojson]
end

(** Resource change notifications. *)
module Resources : sig
  (** Specific resource content updated. *)
  module Updated : sig
    type params = { uri : string } [@@deriving yojson]
  end

  (** Available resources list changed. *)
  module ListChanged : sig
    type params = unit [@@deriving yojson]
  end
end

(** Prompt list change notifications. *)
module Prompts : sig
  (** Available prompts list changed. *)
  module ListChanged : sig
    type params = unit [@@deriving yojson]
  end
end

(** Tool list change notifications. *)
module Tools : sig
  (** Available tools list changed. *)
  module ListChanged : sig
    type params = unit [@@deriving yojson]
  end
end

(** Root directory change notifications. *)
module Roots : sig
  (** Root directories list changed. *)
  module ListChanged : sig
    type params = unit [@@deriving yojson]
  end
end

(** Log message from server. *)
module Message : sig
  type params = {
    level : LogLevel.t;
    logger : string option;
    data : Yojson.Safe.t;
  }
  [@@deriving yojson]
end

type t =
  | Initialized
  | Progress of Progress.params
  | Cancelled of Cancelled.params
  | ResourcesUpdated of Resources.Updated.params
  | ResourcesListChanged
  | PromptsListChanged
  | ToolsListChanged
  | RootsListChanged
  | Message of Message.params
      (** Notification variants for all MCP notifications. *)

val method_name : t -> string
(** [method_name notification] returns JSON-RPC method name. *)

val to_yojson : t -> Yojson.Safe.t
(** [to_yojson notification] converts to JSON parameters. *)

val of_jsonrpc : string -> Yojson.Safe.t option -> (t, string) result
(** [of_jsonrpc method params] parses JSON-RPC into typed notification.

    @param method JSON-RPC method name
    @param params optional parameters
    @return Ok with typed notification or Error with description *)
