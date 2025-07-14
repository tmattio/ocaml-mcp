(** OCaml MCP Server implementation using the SDK *)

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

  (* Initialize merlin client *)
  let merlin = Merlin_client.create ~project_root in

  (* Initialize ocamlformat client *)
  let ocamlformat = Ocamlformat_client.create () in

  (* Initialize dune RPC if enabled *)
  let dune_rpc =
    if config.enable_dune && Sys.getenv_opt "OCAML_MCP_NO_DUNE" = None then (
      Log.debug (fun m -> m "Initializing Dune RPC client");
      let client = Dune_rpc_client.create ~sw ~env ~root:project_root in
      (* Start polling in background *)
      Fiber.fork ~sw (fun () ->
          Log.debug (fun m -> m "Starting Dune RPC polling loop");
          Dune_rpc_client.run client);
      Some client)
    else (
      Log.debug (fun m -> m "Dune RPC disabled");
      None)
  in

  (* Create unified context *)
  let context =
    Context.create ~sw ~env ~project_root ~merlin ~ocamlformat ~dune_rpc
  in

  (* Create SDK server with pagination support *)
  let mcp_logging_config =
    Mcp_sdk.Server.
      {
        enabled = config.enable_mcp_logging;
        initial_level = config.mcp_log_level;
      }
  in
  let server =
    Mcp_sdk.Server.create
      ~server_info:{ name = "ocaml-mcp-server"; version = "0.1.0" }
      ~pagination_config:{ page_size = 10 }
        (* Demonstrate pagination with 10 items per page *)
      ~mcp_logging_config ()
  in

  (* Register tools with unified context *)
  (* Dune tools *)
  Tool_build_status.register server context;
  Tool_build_target.register server context;
  Tool_run_tests.register server context;

  (* OCaml analysis tools *)
  Tool_module_signature.register server context;
  Tool_find_definition.register server context;
  Tool_find_references.register server context;
  Tool_type_at_pos.register server context;
  Tool_project_structure.register server context;
  Tool_eval.register server context;

  (* File system tools with OCaml superpowers *)
  Tool_fs_read.register server context;
  Tool_fs_write.register server context;
  Tool_fs_edit.register server context;

  server

let run ~sw ~env ~connection ~config =
  Log.info (fun m -> m "Starting OCaml MCP Server");
  let server = create_server ~sw ~env ~config in
  let mcp_server = Mcp_sdk.Server.to_mcp_server server in

  (* Set up MCP logging using SDK functionality *)
  Mcp_sdk.Server.setup_mcp_logging server mcp_server;

  Mcp_eio.Connection.serve ~sw connection mcp_server

let run_stdio ~env ~config =
  Log.info (fun m -> m "Starting MCP server in stdio mode");
  Eio.Switch.run @@ fun sw ->
  let transport =
    Mcp_eio.Stdio.create ~stdin:(Eio.Stdenv.stdin env)
      ~stdout:(Eio.Stdenv.stdout env)
  in
  let conn =
    Mcp_eio.Connection.create
      (module Mcp_eio.Stdio : Mcp_eio.Transport.S with type t = _)
      transport
  in
  run ~sw ~env ~connection:conn ~config;
  Log.info (fun m -> m "Server run completed, exiting switch")
