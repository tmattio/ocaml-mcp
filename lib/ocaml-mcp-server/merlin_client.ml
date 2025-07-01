(** Merlin client for OCaml analysis *)

open Merlin_kernel

(* Setup logging *)
let src = Logs.Src.create "merlin-client" ~doc:"Merlin client logging"

module Log = (val Logs.src_log src : Logs.LOG)

type t = { config : Mconfig.t }

(** Create a new merlin client *)
let create ~project_root =
  let config =
    let open Mconfig in
    let config = Mconfig.initial in
    let config =
      {
        config with
        query = { config.query with directory = project_root };
        merlin =
          {
            config.merlin with
            build_path =
              [
                Filename.concat project_root "_build/default";
                Filename.concat project_root "_build/install/default/lib";
              ];
            source_path = [ project_root ];
            cmi_path = [ Filename.concat project_root "_build/default" ];
          };
      }
    in
    config
  in
  { config }

(** Create a merlin document from source text *)
let create_document t ~source_path:path ~source_text =
  let source = Msource.make source_text in
  let config =
    (* Update config with file-specific settings *)
    let open Mconfig in
    {
      t.config with
      query =
        {
          t.config.query with
          verbosity = t.config.query.verbosity;
          directory = Filename.dirname path;
        };
    }
  in
  Mpipeline.make config source

(** Execute a query on a document *)
let query_document ~pipeline query =
  Mpipeline.with_pipeline pipeline (fun () ->
      Query_commands.dispatch pipeline query)

(** Find definition of a symbol at position *)
let find_definition t ~source_path ~source_text ~line ~col =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let pos = `Logical (line, col) in
    let query = Query_protocol.Locate (None, `ML, pos) in
    match query_document ~pipeline query with
    | `Found (path_opt, lex_pos) -> (
        match path_opt with
        | Some path -> Ok (path, lex_pos)
        | None -> Error "Definition found but no path available")
    | `Not_found (reason, _) ->
        Error (Printf.sprintf "Definition not found: %s" reason)
    | `Not_in_env reason ->
        Error (Printf.sprintf "Not in environment: %s" reason)
    | `File_not_found msg -> Error (Printf.sprintf "File not found: %s" msg)
    | `At_origin -> Error "Already at definition origin"
    | `Builtin msg ->
        Error (Printf.sprintf "This is a built-in definition: %s" msg)
    | `Invalid_context -> Error "Invalid context"
  with exn ->
    Error
      (Printf.sprintf "Failed to find definition: %s" (Printexc.to_string exn))

(** Find all references to a symbol at position *)
let find_references t ~source_path ~source_text ~line ~col =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let pos = `Logical (line, col) in
    let query = Query_protocol.Occurrences (`Ident_at pos, `Project) in
    match query_document ~pipeline query with
    | occurrences, _status ->
        let refs =
          List.filter_map
            (fun (occurrence : Query_protocol.occurrence) ->
              match occurrence.is_stale with
              | true -> None
              | false ->
                  let fname = occurrence.loc.loc_start.pos_fname in
                  Some (occurrence.loc, fname))
            occurrences
        in
        Ok refs
  with exn ->
    Error
      (Printf.sprintf "Failed to find references: %s" (Printexc.to_string exn))

(** Get type at position *)
let type_at_pos t ~source_path ~source_text ~line ~col =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let pos = `Logical (line, col) in
    let query = Query_protocol.Type_enclosing (None, pos, Some 0) in
    match query_document ~pipeline query with
    | [] -> Error "No type information at this position"
    | enclosings -> (
        (* Get the innermost type *)
        let loc, typ, _tail = List.hd enclosings in
        match typ with
        | `String s -> Ok (loc, s)
        | `Index _ -> Error "Got index instead of type string")
  with exn ->
    Error (Printf.sprintf "Failed to get type: %s" (Printexc.to_string exn))

(** Get completions at position *)
let completions t ~source_path ~source_text ~line ~col ~prefix =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let pos = `Logical (line, col) in
    let query = Query_protocol.Complete_prefix (prefix, pos, [], false, true) in
    match query_document ~pipeline query with
    | { Query_protocol.Compl.entries; _ } -> Ok entries
  with exn ->
    Error
      (Printf.sprintf "Failed to get completions: %s" (Printexc.to_string exn))

(** Get document symbols (outline) *)
let document_symbols t ~source_path ~source_text =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let query = Query_protocol.Outline in
    match query_document ~pipeline query with outline -> Ok outline
  with exn ->
    Error
      (Printf.sprintf "Failed to get document symbols: %s"
         (Printexc.to_string exn))

(** Get errors and warnings *)
let diagnostics t ~source_path ~source_text =
  try
    let pipeline = create_document t ~source_path ~source_text in
    let query =
      Query_protocol.Errors { lexing = true; parsing = true; typing = true }
    in
    match query_document ~pipeline query with errors -> Ok errors
  with exn ->
    Error
      (Printf.sprintf "Failed to get diagnostics: %s" (Printexc.to_string exn))
