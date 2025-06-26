(** MCP client implementation.

    This module provides a client for connecting to MCP servers. Clients can
    discover and use tools, resources, and prompts exposed by servers. *)

open Mcp_types
open Mcp_protocol

type notification_handler = {
  on_resources_updated : Mcp_notification.Resources.Updated.params -> unit;
  on_resources_list_changed :
    Mcp_notification.Resources.ListChanged.params -> unit;
  on_prompts_list_changed : Mcp_notification.Prompts.ListChanged.params -> unit;
  on_tools_list_changed : Mcp_notification.Tools.ListChanged.params -> unit;
  on_message : Mcp_notification.Message.params -> unit;
}
(** Callbacks for handling server notifications. *)

type request_handler = {
  on_sampling_create_message :
    Mcp_request.Sampling.CreateMessage.params ->
    (Mcp_request.Sampling.CreateMessage.result, string) result;
  on_elicitation_create :
    Mcp_request.Elicitation.Create.params ->
    (Mcp_request.Elicitation.Create.result, string) result;
  on_roots_list :
    Mcp_request.Roots.List.params ->
    (Mcp_request.Roots.List.result, string) result;
}
(** Callbacks for handling server requests. *)

type t
(** Client instance managing connection state and requests. *)

val create :
  ?request_handler:request_handler ->
  notification_handler:notification_handler ->
  client_info:ClientInfo.t ->
  client_capabilities:Capabilities.client ->
  unit ->
  t
(** [create ~notification_handler ~client_info ~client_capabilities] creates new
    client.

    @param notification_handler callbacks for server notifications
    @param client_info client name and version
    @param client_capabilities supported client features *)

val send_request :
  t ->
  Mcp_request.t ->
  ((Yojson.Safe.t, Jsonrpc.Response.Error.t) result -> unit) ->
  outgoing_message
(** [send_request t request callback] sends request and registers callback.

    Returns outgoing message to be sent via transport. *)

val send_notification : t -> Mcp_notification.t -> outgoing_message
(** [send_notification t notification] creates notification message.

    Returns outgoing message to be sent via transport. *)

val handle_message : t -> incoming_message -> outgoing_message option
(** [handle_message t msg] processes incoming message from server.

    Returns optional response to send back. *)

val initialize :
  t ->
  protocol_version:string ->
  ((Mcp_request.Initialize.result, string) result -> unit) ->
  outgoing_message
(** [initialize t ~protocol_version callback] performs handshake with server.

    Must be called before other requests. Negotiates protocol version and
    exchanges capabilities. *)

val is_initialized : t -> bool
(** [is_initialized t] returns true if handshake completed. *)

val get_server_capabilities : t -> Capabilities.server option
(** [get_server_capabilities t] returns server capabilities after
    initialization. *)

val get_server_info : t -> ServerInfo.t option
(** [get_server_info t] returns server name and version after initialization. *)

(** {1 Request Helpers}

    Convenience functions for common MCP requests. *)

val resources_list :
  t ->
  ?cursor:cursor ->
  ((Mcp_request.Resources.List.result, string) result -> unit) ->
  outgoing_message
(** [resources_list t ?cursor callback] lists available resources.

    @param cursor optional pagination cursor *)

val resources_read :
  t ->
  uri:string ->
  ((Mcp_request.Resources.Read.result, string) result -> unit) ->
  outgoing_message
(** [resources_read t ~uri callback] reads resource contents. *)

val prompts_list :
  t ->
  ?cursor:cursor ->
  ((Mcp_request.Prompts.List.result, string) result -> unit) ->
  outgoing_message
(** [prompts_list t ?cursor callback] lists available prompts.

    @param cursor optional pagination cursor *)

val prompts_get :
  t ->
  name:string ->
  ?arguments:(string * string) list ->
  ((Mcp_request.Prompts.Get.result, string) result -> unit) ->
  outgoing_message
(** [prompts_get t ~name ?arguments callback] retrieves prompt with arguments.
*)

val tools_list :
  t ->
  ?cursor:cursor ->
  ((Mcp_request.Tools.List.result, string) result -> unit) ->
  outgoing_message
(** [tools_list t ?cursor callback] lists available tools.

    @param cursor optional pagination cursor *)

val tools_call :
  t ->
  name:string ->
  ?arguments:Yojson.Safe.t ->
  ((Mcp_request.Tools.Call.result, string) result -> unit) ->
  outgoing_message
(** [tools_call t ~name ?arguments callback] invokes tool with arguments. *)

val default_notification_handler : notification_handler
(** [default_notification_handler] provides no-op implementations for all
    callbacks. *)

val default_request_handler : request_handler
(** [default_request_handler] returns errors for all server requests. *)
