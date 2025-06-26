(** Logging infrastructure for MCP *)

type level = Debug | Info | Warn | Error

val set_level : level -> unit
(** Set the current logging level *)

val debug : ('a, unit, string, unit) format4 -> 'a
(** Log a debug message *)

val info : ('a, unit, string, unit) format4 -> 'a
(** Log an info message *)

val warn : ('a, unit, string, unit) format4 -> 'a
(** Log a warning message *)

val error : ('a, unit, string, unit) format4 -> 'a
(** Log an error message *)
