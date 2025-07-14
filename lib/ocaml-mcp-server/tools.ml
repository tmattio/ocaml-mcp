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

let build_status : (module S) = (module Tool_build_status)
let build_target : (module S) = (module Tool_build_target)
let run_tests : (module S) = (module Tool_run_tests)
let module_signature : (module S) = (module Tool_module_signature)
let find_definition : (module S) = (module Tool_find_definition)
let find_references : (module S) = (module Tool_find_references)
let type_at_pos : (module S) = (module Tool_type_at_pos)
let project_structure : (module S) = (module Tool_project_structure)
let eval : (module S) = (module Tool_eval)
let fs_read : (module S) = (module Tool_fs_read)
let fs_write : (module S) = (module Tool_fs_write)
let fs_edit : (module S) = (module Tool_fs_edit)

let all =
  [
    build_status;
    build_target;
    run_tests;
    module_signature;
    find_definition;
    find_references;
    type_at_pos;
    project_structure;
    eval;
    fs_read;
    fs_write;
    fs_edit;
  ]
