(** Connection management for MCP over various transports.

    This module provides high-level connection handling for MCP clients and
    servers. It manages the lifecycle of connections, message routing, and
    integration with the transport layer. *)

type t
(** Connection instance managing transport and message handling. *)

val create :
  clock:_ Eio.Time.clock -> (module Transport.S with type t = 'a) -> 'a -> t
(** [create ~clock transport_module transport_instance] creates connection.

    Wraps any transport implementation with connection management.
    @param clock The clock to use for timing operations *)

val send : t -> Mcp.Protocol.outgoing_message -> unit
(** [send t msg] sends outgoing message through transport. *)

val recv : t -> ?timeout:float -> unit -> Mcp.Protocol.incoming_message option
(** [recv t ?timeout ()] receives and parses next incoming message.

    Returns [None] on EOF or parse error.
    @param timeout Optional timeout in seconds
    @raise Eio.Time.Timeout if timeout is specified and the operation times out.
*)

val close : t -> unit
(** [close t] closes connection and underlying transport. *)

val serve : sw:Eio.Switch.t -> t -> Mcp.Server.t -> unit
(** [serve ~sw t server] runs server on connection.

    Processes incoming messages until EOF or error. Uses switch for structured
    concurrency. *)

val run_client : sw:Eio.Switch.t -> t -> Mcp.Client.t -> unit
(** [run_client ~sw t client] runs client on connection.

    Processes incoming messages until EOF or error. Uses switch for structured
    concurrency. *)

val send_request :
  t ->
  Mcp.Client.t ->
  Mcp.Request.t ->
  ((Yojson.Safe.t, Jsonrpc.Response.Error.t) result -> unit) ->
  unit
(** [send_request t client request callback] sends client request.

    Convenience function that registers callback and sends request. *)

val send_notification :
  t ->
  [< `Server of Mcp.Server.t * Mcp.Notification.t
  | `Client of Mcp.Client.t * Mcp.Notification.t ] ->
  unit
(** [send_notification t notification] sends notification from client or server.
*)
