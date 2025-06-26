(** Transport interface for MCP.

    This module defines the common interface for all transport implementations.
    Transports handle the low-level sending and receiving of JSON-RPC packets
    over different communication channels. *)

(** Transport module signature. *)
module type S = sig
  type t
  (** Transport instance. *)

  val send : t -> Jsonrpc.Packet.t -> unit
  (** [send t packet] sends JSON-RPC packet over transport. *)

  val recv : t -> Jsonrpc.Packet.t option
  (** [recv t] receives next JSON-RPC packet.

      Returns [None] when transport is closed or EOF reached. *)

  val close : t -> unit
  (** [close t] closes transport and releases resources. *)
end
