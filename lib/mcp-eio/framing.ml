(** Message framing utilities for MCP using Content-Length headers *)

open Eio

(* Convert between jsonrpc's Json.t and Yojson.Safe.t *)
let rec json_to_yojson (json : Jsonrpc.Json.t) : Yojson.Safe.t =
  match json with
  | `Assoc lst -> `Assoc (List.map (fun (k, v) -> (k, json_to_yojson v)) lst)
  | `Bool b -> `Bool b
  | `Float f -> `Float f
  | `Int i -> `Int i
  | `Intlit s -> `Intlit s
  | `List lst -> `List (List.map json_to_yojson lst)
  | `Null -> `Null
  | `String s -> `String s
  | `Tuple lst -> `List (List.map json_to_yojson lst)
  | `Variant (name, opt) -> (
      match opt with
      | None -> `Assoc [ ("variant", `String name) ]
      | Some v ->
          `Assoc [ ("variant", `String name); ("value", json_to_yojson v) ])

let rec yojson_to_json (yojson : Yojson.Safe.t) : Jsonrpc.Json.t =
  match yojson with
  | `Assoc lst -> `Assoc (List.map (fun (k, v) -> (k, yojson_to_json v)) lst)
  | `Bool b -> `Bool b
  | `Float f -> `Float f
  | `Int i -> `Int i
  | `Intlit s -> `Intlit s
  | `List lst -> `List (List.map yojson_to_json lst)
  | `Null -> `Null
  | `String s -> `String s
  | `Tuple lst -> `List (List.map yojson_to_json lst)
  | `Variant (name, arg) ->
      match arg with
      | None -> `Assoc [ ("variant", `String name) ]
      | Some v ->
          `Assoc [ ("variant", `String name); ("value", yojson_to_json v) ]

let write_packet (sink : _ Flow.sink) (packet : Jsonrpc.Packet.t) =
  let json = Jsonrpc.Packet.yojson_of_t packet in
  let yojson = json_to_yojson json in
  let content = Yojson.Safe.to_string yojson in
  let content_length = String.length content in
  let header = Printf.sprintf "Content-Length: %d\r\n\r\n" content_length in
  Flow.write sink [ Cstruct.of_string header; Cstruct.of_string content ]

let read_headers (reader : Buf_read.t) : (string * string) list =
  let rec loop acc =
    match Buf_read.line reader with
    | "" | "\r" -> List.rev acc  (* Empty line signals end of headers *)
    | line ->
        (* Remove trailing \r if present *)
        let line = 
          if String.length line > 0 && line.[String.length line - 1] = '\r' then
            String.sub line 0 (String.length line - 1)
          else line
        in
        (* Parse header *)
        (match String.index_opt line ':' with
         | None -> loop acc  (* Skip malformed headers *)
         | Some idx ->
             let key = String.sub line 0 idx in
             let value_start = idx + 1 in
             let value_len = String.length line - value_start in
             let value = String.sub line value_start value_len |> String.trim in
             loop ((key, value) :: acc))
    | exception End_of_file -> List.rev acc
  in
  loop []

let read_packet (reader : Buf_read.t) : Jsonrpc.Packet.t option =
  try
    let headers = read_headers reader in
    match List.assoc_opt "Content-Length" headers with
    | None -> None  (* No Content-Length header *)
    | Some len_str -> (
        match int_of_string_opt len_str with
        | None -> failwith "Invalid Content-Length value"
        | Some len ->
            let content = Buf_read.take len reader in
            let yojson = Yojson.Safe.from_string content in
            let json = yojson_to_json yojson in
            Some (Jsonrpc.Packet.t_of_yojson json))
  with
  | End_of_file -> None
  | exn ->
      failwith
        (Printf.sprintf "Packet parse error: %s" (Printexc.to_string exn))