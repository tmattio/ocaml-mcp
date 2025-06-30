(** TCP/Unix socket transport implementation for MCP.

    This module provides transport implementations for both client and server
    communication over TCP or Unix domain sockets. It handles socket lifecycle
    management and integrates with Eio's networking capabilities. *)

type t
(** Transport instance for socket communication. *)

val create_from_socket : _ Eio.Net.stream_socket -> t
(** [create_from_socket socket] creates a transport from an existing socket. *)

val create_server :
  net:_ Eio.Net.t -> sw:Eio.Switch.t -> Eio.Net.Sockaddr.stream -> t
(** [create_server ~net ~sw addr] creates server socket transport.

    Listens on the given address and accepts exactly one connection. The socket
    is managed by the provided switch. *)

val create_client :
  net:_ Eio.Net.t -> sw:Eio.Switch.t -> Eio.Net.Sockaddr.stream -> t
(** [create_client ~net ~sw addr] creates client socket transport.

    Connects to the server at the given address. The connection is managed by
    the provided switch. *)

include Transport.S with type t := t
(** Implements the transport interface. *)
