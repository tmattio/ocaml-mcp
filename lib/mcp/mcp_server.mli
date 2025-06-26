(** MCP server implementation.

    This module provides a server for exposing tools, resources, and prompts to
    MCP clients. Servers handle requests and send notifications according to
    their declared capabilities. *)

open Mcp_types
open Mcp_protocol

type handler = {
  on_initialize :
    Mcp_request.Initialize.params ->
    (Mcp_request.Initialize.result, string) result;
  on_resources_list :
    Mcp_request.Resources.List.params ->
    (Mcp_request.Resources.List.result, string) result;
  on_resources_read :
    Mcp_request.Resources.Read.params ->
    (Mcp_request.Resources.Read.result, string) result;
  on_resources_subscribe :
    Mcp_request.Resources.Subscribe.params ->
    (Mcp_request.Resources.Subscribe.result, string) result;
  on_resources_unsubscribe :
    Mcp_request.Resources.Unsubscribe.params ->
    (Mcp_request.Resources.Unsubscribe.result, string) result;
  on_resources_templates_list :
    Mcp_request.Resources.Templates.List.params ->
    (Mcp_request.Resources.Templates.List.result, string) result;
  on_prompts_list :
    Mcp_request.Prompts.List.params ->
    (Mcp_request.Prompts.List.result, string) result;
  on_prompts_get :
    Mcp_request.Prompts.Get.params ->
    (Mcp_request.Prompts.Get.result, string) result;
  on_tools_list :
    Mcp_request.Tools.List.params ->
    (Mcp_request.Tools.List.result, string) result;
  on_tools_call :
    Mcp_request.Tools.Call.params ->
    (Mcp_request.Tools.Call.result, string) result;
  on_sampling_create_message :
    Mcp_request.Sampling.CreateMessage.params ->
    (Mcp_request.Sampling.CreateMessage.result, string) result;
  on_elicitation_create :
    Mcp_request.Elicitation.Create.params ->
    (Mcp_request.Elicitation.Create.result, string) result;
  on_logging_set_level :
    Mcp_request.Logging.SetLevel.params ->
    (Mcp_request.Logging.SetLevel.result, string) result;
  on_completion_complete :
    Mcp_request.Completion.Complete.params ->
    (Mcp_request.Completion.Complete.result, string) result;
  on_roots_list :
    Mcp_request.Roots.List.params ->
    (Mcp_request.Roots.List.result, string) result;
  on_ping : Mcp_request.Ping.params -> (Mcp_request.Ping.result, string) result;
}
(** Callbacks for handling client requests. Each callback returns Ok with result
    or Error with description. *)

type notification_handler = {
  on_initialized : Mcp_notification.Initialized.params -> unit;
  on_progress : Mcp_notification.Progress.params -> unit;
  on_cancelled : Mcp_notification.Cancelled.params -> unit;
  on_roots_list_changed : Mcp_notification.Roots.ListChanged.params -> unit;
}
(** Callbacks for handling client notifications. *)

type t
(** Server instance managing connection state and handlers. *)

val create :
  handler:handler ->
  notification_handler:notification_handler ->
  server_info:ServerInfo.t ->
  server_capabilities:Capabilities.server ->
  t
(** [create ~handler ~notification_handler ~server_info ~server_capabilities]
    creates server.

    @param handler callbacks for handling requests
    @param notification_handler callbacks for notifications
    @param server_info server name and version
    @param server_capabilities supported server features *)

val handle_message : t -> incoming_message -> outgoing_message option
(** [handle_message t msg] processes incoming message from client.

    Returns optional response to send back. *)

val send_notification : t -> Mcp_notification.t -> outgoing_message
(** [send_notification t notification] creates notification message.

    Returns outgoing message to be sent via transport. *)

val is_initialized : t -> bool
(** [is_initialized t] returns true if handshake completed. *)

val get_client_capabilities : t -> Capabilities.client option
(** [get_client_capabilities t] returns client capabilities after
    initialization. *)

val default_handler : handler
(** [default_handler] returns "Not implemented" for all methods except ping. *)

val default_notification_handler : notification_handler
(** [default_notification_handler] provides no-op implementations for all
    callbacks. *)
