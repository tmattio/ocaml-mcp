(** OCaml MCP Server implementation using the async SDK *)

open Eio

(* Setup logging *)
let src = Logs.Src.create "ocaml-mcp-server" ~doc:"OCaml MCP Server logging"

module Log = (val Logs.src_log src : Logs.LOG)

type config = {
  project_root : string option;
  enable_dune : bool;
  enable_mcp_logging : bool;
  mcp_log_level : Mcp.Types.LogLevel.t option;
}

let default_config =
  {
    project_root = None;
    enable_dune = true;
    enable_mcp_logging = true;
    mcp_log_level = None;
  }

let find_project_root env =
  (* Look for dune-project or .git in parent directories *)
  let fs = Stdenv.fs env in
  let rec find_root dir =
    let dune_project_path = Path.(fs / dir / "dune-project") in
    let git_path = Path.(fs / dir / ".git") in
    match
      ( Path.kind ~follow:false dune_project_path,
        Path.kind ~follow:false git_path )
    with
    | (`Regular_file | `Directory), _ | _, `Directory -> Some dir
    | _ ->
        let parent = Filename.dirname dir in
        if parent = dir then None else find_root parent
  in
  let cwd = Stdenv.cwd env in
  match Path.native cwd with Some cwd_str -> find_root cwd_str | None -> None

let create_server ~sw ~env ~config =
  let project_root =
    match config.project_root with
    | Some root -> root
    | None -> (
        match find_project_root env with
        | Some root -> root
        | None -> (
            (* Fall back to current working directory *)
            match Path.native (Stdenv.cwd env) with
            | Some cwd -> cwd
            | None -> "."))
  in

  (* Create ocaml-platform-sdk instance *)
  let sdk =
    Ocaml_platform_sdk.create ~sw ~env ~project_root
      ~enable_dune:
        (config.enable_dune && Sys.getenv_opt "OCAML_MCP_NO_DUNE" = None)
      ()
  in

  (* Create async SDK server with pagination support *)
  let mcp_logging_config =
    Mcp_sdk.Server.
      {
        enabled = config.enable_mcp_logging;
        initial_level = config.mcp_log_level;
      }
  in
  let server =
    Mcp_sdk_eio.Server.create
      ~server_info:{ name = "ocaml-mcp-server"; version = "0.1.0" }
      ~pagination_config:{ page_size = 10 }
        (* Demonstrate pagination with 10 items per page *)
      ~mcp_logging_config ()
  in

  (* Register all tools with async support *)
  Tool_adapter.register_all server sw env sdk;

  server

let run ~sw ~env ~connection ~config =
  Log.info (fun m -> m "Starting OCaml MCP Server (async)");
  let server = create_server ~sw ~env ~config in
  (* Run the async server - it handles MCP logging automatically *)
  Mcp_sdk_eio.Server.run ~sw ~env server connection

let run_stdio ~env ~config =
  Log.info (fun m -> m "Starting MCP server in stdio mode");
  Eio.Switch.run @@ fun sw ->
  let transport =
    Mcp_eio.Stdio.create ~stdin:(Eio.Stdenv.stdin env)
      ~stdout:(Eio.Stdenv.stdout env)
  in
  let clock = Eio.Stdenv.clock env in
  let conn =
    Mcp_eio.Connection.create ~clock
      (module Mcp_eio.Stdio : Mcp_eio.Transport.S with type t = _)
      transport
  in
  run ~sw ~env ~connection:conn ~config;
  Log.info (fun m -> m "Server run completed, exiting switch")

module type S = Tool_adapter.S

let build_status : (module S) = (module Build_status)
let build_target : (module S) = (module Build_target)
let eval : (module S) = (module Eval)
let find_definition : (module S) = (module Find_definition)
let find_references : (module S) = (module Find_references)
let fs_edit : (module S) = (module Fs_edit)
let fs_read : (module S) = (module Fs_read)
let fs_write : (module S) = (module Fs_write)
let module_signature : (module S) = (module Module_signature)
let project_structure : (module S) = (module Project_structure)
let run_tests : (module S) = (module Run_tests)
let type_at_pos : (module S) = (module Type_at_pos)
