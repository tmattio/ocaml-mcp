(** MCP protocol message handling.

    This module handles JSON-RPC message parsing and serialization for the Model
    Context Protocol. It provides types and functions for converting between MCP
    messages and JSON-RPC packets. *)

open Jsonrpc

type incoming_message =
  | Request of Id.t * Mcp_request.t
  | Notification of Mcp_notification.t
  | Response of Id.t * (Yojson.Safe.t, Response.Error.t) result
  | Batch_request of incoming_message list
  | Batch_response of incoming_message list
      (** Messages received from remote endpoint. *)

type outgoing_message =
  | Request of Id.t * string * Yojson.Safe.t option
  | Notification of string * Yojson.Safe.t option
  | Response of Id.t * (Yojson.Safe.t, Response.Error.t) result
  | Batch_response of outgoing_message list
      (** Messages to send to remote endpoint. *)

val parse_message : Packet.t -> (incoming_message, string) result
(** [parse_message packet] parses JSON-RPC packet into incoming message.

    @return Ok with parsed message or Error with description *)

val outgoing_to_message : outgoing_message -> Packet.t
(** [outgoing_to_message msg] converts outgoing message to JSON-RPC packet. *)

val request_to_outgoing : id:Id.t -> Mcp_request.t -> outgoing_message
(** [request_to_outgoing ~id request] creates outgoing request message. *)

val notification_to_outgoing : Mcp_notification.t -> outgoing_message
(** [notification_to_outgoing notification] creates outgoing notification
    message. *)

val response_to_outgoing : id:Id.t -> Mcp_request.response -> outgoing_message
(** [response_to_outgoing ~id response] creates outgoing response message. *)

val error_to_outgoing :
  id:Id.t ->
  code:int ->
  message:string ->
  ?data:Yojson.Safe.t ->
  unit ->
  outgoing_message
(** [error_to_outgoing ~id ~code ~message ?data ()] creates error response.

    @param id request identifier
    @param code numeric error code
    @param message human-readable error description
    @param data optional error details *)
