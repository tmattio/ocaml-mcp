(** Standard I/O transport implementation for MCP.

    This module provides a transport implementation that communicates over
    standard input and output streams. It's typically used for processes that
    communicate via stdin/stdout pipes. *)

type t
(** Transport instance for stdio communication. *)

val create : stdin:_ Eio.Flow.source -> stdout:_ Eio.Flow.sink -> t
(** [create ~stdin ~stdout] creates stdio transport.

    Uses provided input and output streams for communication. *)

include Transport.S with type t := t
(** Implements the transport interface. *)
