(** Message framing utilities for newline-delimited JSON.

    This module handles the serialization and deserialization of JSON-RPC
    messages using newline-delimited JSON (NDJSON) format. It provides
    conversion between different JSON representations and I/O operations. *)

val json_to_yojson : Jsonrpc.Json.t -> Yojson.Safe.t
(** [json_to_yojson json] converts from jsonrpc to Yojson format. *)

val yojson_to_json : Yojson.Safe.t -> Jsonrpc.Json.t
(** [yojson_to_json yojson] converts from Yojson to jsonrpc format. *)

val write_packet : _ Eio.Flow.sink -> Jsonrpc.Packet.t -> unit
(** [write_packet sink packet] writes packet as newline-delimited JSON. *)

val read_packet : Eio.Buf_read.t -> Jsonrpc.Packet.t option
(** [read_packet reader] reads next newline-delimited JSON packet.

    Returns [None] on EOF. *)
