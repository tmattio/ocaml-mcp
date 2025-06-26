(** In-memory transport implementation for testing.

    This module provides a transport implementation that operates entirely in
    memory without any real I/O. It's primarily used for testing MCP
    implementations without requiring actual network or stdio connections. *)

type t
(** Transport instance for in-memory communication. *)

val create_pair : unit -> t * t
(** [create_pair ()] creates connected transport pair.

    Returns two transports that are connected to each other. Messages sent on
    one transport will be received on the other, simulating bidirectional
    communication. Useful for testing client-server interactions. *)

include Transport.S with type t := t
(** Implements the transport interface. *)
