(** Message framing utilities for newline-delimited JSON *)

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

let write_packet (sink : _ Flow.sink) (packet : Jsonrpc.Packet.t) =
  let json = Jsonrpc.Packet.yojson_of_t packet in
  let yojson = json_to_yojson json in
  let line = Yojson.Safe.to_string yojson in
  Flow.write sink [ Cstruct.of_string line; Cstruct.of_string "\n" ]

let read_packet (reader : Buf_read.t) : Jsonrpc.Packet.t option =
  match Buf_read.line reader with
  | "" -> None (* Empty line, likely EOF *)
  | line -> (
      try
        let yojson = Yojson.Safe.from_string line in
        let json = yojson_to_json yojson in
        Some (Jsonrpc.Packet.t_of_yojson json)
      with exn ->
        failwith
          (Printf.sprintf "Packet parse error: %s" (Printexc.to_string exn)))
  | exception End_of_file -> None
