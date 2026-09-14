(** Incremental parser for Server-Sent Events (SSE) streams *)

type event = { name : string option; data : string }
type t = { mutable name : string option; mutable data : string list }

let create () = { name = None; data = [] }

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

(* A single space after the colon is stripped, per the SSE specification. *)
let field_value line colon =
  let start = colon + 1 in
  let start =
    if start < String.length line && line.[start] = ' ' then start + 1
    else start
  in
  String.sub line start (String.length line - start)

let feed_line t line =
  let line = strip_cr line in
  if line = "" then (
    let event =
      match t.data with
      | [] -> None
      | data ->
          Some
            ({ name = t.name; data = String.concat "\n" (List.rev data) }
              : event)
    in
    t.name <- None;
    t.data <- [];
    event)
  else if line.[0] = ':' then None
  else begin
    let field, value =
      match String.index_opt line ':' with
      | None -> (line, "")
      | Some colon -> (String.sub line 0 colon, field_value line colon)
    in
    (match field with
    | "data" -> t.data <- value :: t.data
    | "event" -> t.name <- Some value
    | _ -> ());
    None
  end
