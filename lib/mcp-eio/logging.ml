(** Logging infrastructure for MCP *)

type level = Debug | Info | Warn | Error

let level_to_string = function
  | Debug -> "DEBUG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Error -> "ERROR"

let current_level = ref Info
let set_level level = current_level := level

let should_log level =
  match (!current_level, level) with
  | Debug, _ -> true
  | Info, Debug -> false
  | Info, _ -> true
  | Warn, (Debug | Info) -> false
  | Warn, _ -> true
  | Error, Error -> true
  | Error, _ -> false

let log level fmt =
  if should_log level then
    Printf.ksprintf
      (fun msg -> Eio.traceln "[%s] %s" (level_to_string level) msg)
      fmt
  else Printf.ksprintf (fun _ -> ()) fmt

let debug fmt = log Debug fmt
let info fmt = log Info fmt
let warn fmt = log Warn fmt
let error fmt = log Error fmt
