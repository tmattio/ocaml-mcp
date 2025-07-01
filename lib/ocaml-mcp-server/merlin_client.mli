(** Merlin client for OCaml analysis *)

type t
(** Merlin client type *)

val create : project_root:string -> t
(** Create a new merlin client for a project *)

val find_definition :
  t ->
  source_path:string ->
  source_text:string ->
  line:int ->
  col:int ->
  (string * Lexing.position, string) result
(** Find definition of a symbol at position *)

val find_references :
  t ->
  source_path:string ->
  source_text:string ->
  line:int ->
  col:int ->
  ((Ocaml_utils.Warnings.loc * string) list, string) result
(** Find all references to a symbol at position *)

val type_at_pos :
  t ->
  source_path:string ->
  source_text:string ->
  line:int ->
  col:int ->
  (Ocaml_utils.Warnings.loc * string, string) result
(** Get type at position *)

val completions :
  t ->
  source_path:string ->
  source_text:string ->
  line:int ->
  col:int ->
  prefix:string ->
  (Query_protocol.Compl.entry list, string) result
(** Get completions at position *)

val document_symbols :
  t ->
  source_path:string ->
  source_text:string ->
  (Query_protocol.item list, string) result
(** Get document symbols (outline) *)

val diagnostics :
  t ->
  source_path:string ->
  source_text:string ->
  (Ocaml_parsing.Location.report list, string) result
(** Get errors and warnings *)
