(** OCaml MCP Server implementation using the SDK *)

open Eio
open Mcp_sdk

(* Setup logging *)
let src = Logs.Src.create "ocaml-mcp-server" ~doc:"OCaml MCP Server logging"

module Log = (val Logs.src_log src : Logs.LOG)

type config = { project_root : string option; enable_dune : bool }

let default_config = { project_root = None; enable_dune = true }

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
  let merlin_client = Merlin_client.create ~project_root in

  (* Initialize ocamlformat client *)
  let ocamlformat_client = Ocamlformat_client.create () in

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

  (* Create SDK server with pagination support *)
  let server =
    Server.create
      ~server_info:{ name = "ocaml-mcp-server"; version = "0.1.0" }
      ~capabilities:
        {
          Mcp.Types.Capabilities.experimental = None;
          logging = None;
          completions = None;
          prompts = None;
          resources = None;
          tools = Some { list_changed = None };
        }
      ~pagination_config:{ page_size = 10 }
        (* Demonstrate pagination with 10 items per page *)
      ()
  in

  (* Register tools *)
  (* Dune tools *)
  Tool_build_status.register server ~dune_rpc;
  Tool_build_target.register server ~sw ~env ~project_root ~dune_rpc;
  Tool_run_tests.register server ~dune_rpc;

  (* OCaml analysis tools *)
  Tool_module_signature.register server ~sw ~env ~project_root;
  Tool_find_definition.register server ~sw ~env ~merlin_client;
  Tool_find_references.register server ~sw ~env ~merlin_client;
  Tool_type_at_pos.register server ~sw ~env ~merlin_client;
  Tool_project_structure.register server ~sw ~env ~project_root;
  Tool_eval.register server ~sw ~env ~project_root;

  (* File system tools with OCaml superpowers *)
  Tool_fs_read.register server ~sw ~env ~merlin_client ~project_root;
  Tool_fs_write.register server ~sw ~env ~merlin_client ~ocamlformat_client
    ~project_root;
  Tool_fs_edit.register server ~sw ~env ~merlin_client ~ocamlformat_client
    ~project_root;

  server

let run ~sw ~env ~connection ~config =
  Log.info (fun m -> m "Starting OCaml MCP Server");
  let server = create_server ~sw ~env ~config in
  let mcp_server = Server.to_mcp_server server in
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
