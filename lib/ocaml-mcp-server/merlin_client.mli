(** Merlin library integration for OCaml code intelligence. *)

open Eio

type t

type signature_item =
  | Value of string * string  (** name, type *)
  | Type of string * string  (** name, definition *)
  | Module of string * signature_item list  (** name, contents *)
  | Exception of string * string  (** name, type *)
[@@deriving yojson]

val create :
  sw:Switch.t ->
  mgr:[> [ `Generic | `Unix ] Process.mgr_ty ] Std.r ->
  project_root:string ->
  t
(** [create ~sw ~mgr ~project_root] creates Merlin client. *)

val get_module_signature : t -> module_path:string list -> signature_item list
(** [get_module_signature t ~module_path] retrieves module signature.

    Example: [~module_path:["List"]] or [~module_path:["String"; "Map"]]. *)

val type_enclosing : t -> file:string -> line:int -> col:int -> string option
(** [type_enclosing t ~file ~line ~col] returns type at position. *)

val complete :
  t ->
  file:string ->
  line:int ->
  col:int ->
  prefix:string ->
  (string * string) list
(** [complete t ~file ~line ~col ~prefix] returns completions as (name, type)
    pairs. *)

val load_file : t -> file:string -> content:string -> unit
(** [load_file t ~file ~content] caches file content for queries. *)

val close : t -> unit
(** [close t] releases resources. *)
