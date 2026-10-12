(** Message framing utilities for newline-delimited JSON.

    This module handles the serialization and deserialization of JSON-RPC
    messages using newline-delimited JSON (NDJSON) format. It provides
    conversion between different JSON representations and I/O operations. *)

open Eio

(* Explicit JSON-RPC dependency adapters. *)
let json_to_jsont = Mcp.Json.of_jsonrpc
let jsont_to_json = Mcp.Json.to_jsonrpc

let write_packet (sink : _ Flow.sink) (packet : Jsonrpc.Packet.t) =
  let json = Jsonrpc.Packet.yojson_of_t packet in
  let yojson = json_to_jsont json in
  let content = Mcp.Json.to_string yojson in
  (* Write as newline-delimited JSON *)
  Flow.write sink [ Cstruct.of_string content; Cstruct.of_string "\n" ]

let rec read_packet (reader : Buf_read.t) : Jsonrpc.Packet.t option =
  try
    (* Read a single line of JSON *)
    let line = Buf_read.line reader in
    (* Remove trailing \r if present (in case of \r\n line endings) *)
    let line =
      if String.length line > 0 && line.[String.length line - 1] = '\r' then
        String.sub line 0 (String.length line - 1)
      else line
    in
    (* Skip empty lines *)
    if String.length line = 0 then read_packet reader
    else
      let yojson = Mcp.Json.of_string line in
      let json = jsont_to_json yojson in
      Some (Jsonrpc.Packet.t_of_yojson json)
  with
  | End_of_file -> None
  | exn ->
      failwith
        (Printf.sprintf "Packet parse error: %s" (Printexc.to_string exn))
