(** All available tools for the OCaml MCP server *)

module type S = sig
  val name : string
  val description : string

  module Args : sig
    type t

    val to_yojson : t -> Yojson.Safe.t
    val of_yojson : Yojson.Safe.t -> (t, string) result
    val schema : unit -> Yojson.Safe.t
  end

  val execute :
    Context.t -> Args.t -> (Mcp.Request.Tools.Call.result, string) result

  val register : Mcp_sdk.Server.t -> Context.t -> unit
end

val build_status : (module S)
val build_target : (module S)
val run_tests : (module S)
val module_signature : (module S)
val find_definition : (module S)
val find_references : (module S)
val type_at_pos : (module S)
val project_structure : (module S)
val eval : (module S)
val fs_read : (module S)
val fs_write : (module S)
val fs_edit : (module S)
val all : (module S) list
