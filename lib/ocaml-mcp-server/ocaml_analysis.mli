(** OCaml code analysis - module signatures and build artifacts *)

(** {1 Module Signatures} *)

val get_module_signature :
  project_root:string -> module_path:string list -> (string, string) result
(** Get module signature from build artifacts (.cmi or .cmt files) *)
