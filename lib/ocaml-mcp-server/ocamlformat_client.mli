(** OCamlformat client using the library directly *)

type t
(** The type of an OCamlformat client *)

val create : unit -> t
(** Create a new OCamlformat client instance *)


val format_type : t -> typ:string -> (string, [> `Msg of string]) result
(** Format a type expression *)

val format_doc : t -> path:string -> content:string -> (string, string) result
(** Format a document with the given path and content *)