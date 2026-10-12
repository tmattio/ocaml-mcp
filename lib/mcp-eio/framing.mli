(** Message framing utilities for newline-delimited JSON.

    This module handles the serialization and deserialization of JSON-RPC
    messages using newline-delimited JSON (NDJSON) format. It provides
    conversion between different JSON representations and I/O operations. *)

val json_to_jsont : Jsonrpc.Json.t -> Jsont.json
(** [json_to_jsont json] converts from jsonrpc to Jsont format. *)

val jsont_to_json : Jsont.json -> Jsonrpc.Json.t
(** [jsont_to_json json] converts from Jsont to jsonrpc format. *)

val write_packet : _ Eio.Flow.sink -> Jsonrpc.Packet.t -> unit
(** [write_packet sink packet] writes packet as newline-delimited JSON. *)

val read_packet : Eio.Buf_read.t -> Jsonrpc.Packet.t option
(** [read_packet reader] reads next newline-delimited JSON packet.

    Returns [None] on EOF. *)
