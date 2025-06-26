(** OCaml MCP Server implementation using the SDK *)

open Eio
open Mcp_sdk

type config = {
  project_root : string option;
  enable_dune : bool;
  enable_merlin : bool;
}

let default_config =
  { project_root = None; enable_dune = true; enable_merlin = true }

let find_project_root () =
  (* Look for dune-project or .git in parent directories *)
  let rec find_root dir =
    if
      Sys.file_exists (Filename.concat dir "dune-project")
      || Sys.file_exists (Filename.concat dir ".git")
    then Some dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then None else find_root parent
  in
  find_root (Sys.getcwd ())

(* Tool argument types *)
type build_status_args = { targets : string list option [@default None] }
[@@deriving yojson]

type module_signature_args = { module_path : string list } [@@deriving yojson]

(* Helper functions for tool implementations *)
let handle_build_status dune_rpc _args _ctx =
  match dune_rpc with
  | None ->
      Ok
        {
          Mcp.Request.Tools.Call.content =
            [
              Mcp.Types.Content.Text
                {
                  Mcp.Types.Content.type_ = "text";
                  text =
                    "Dune RPC not connected. Please run this command from a \
                     dune project.";
                };
            ];
          is_error = Some true;
          structured_content = None;
        }
  | Some dune ->
      (* Get current diagnostics and progress from dune RPC client *)
      let diagnostics = Dune_rpc_client.get_diagnostics dune ~file:"" in
      let progress = Dune_rpc_client.get_progress dune in
      let status_text =
        match progress with
        | Waiting -> "Build waiting..."
        | In_progress { complete; remaining; failed } ->
            Printf.sprintf "Building... (%d/%d completed, %d failed)" complete
              (complete + remaining) failed
        | Failed -> "Build failed"
        | Interrupted -> "Build interrupted"
        | Success ->
            if List.length diagnostics = 0 then "Build successful"
            else "Build completed with warnings"
      in

      let diagnostic_texts =
        List.map
          (fun d ->
            let severity =
              match d.Dune_rpc_client.severity with
              | `Error -> "ERROR"
              | `Warning -> "WARNING"
            in
            Printf.sprintf "[%s] %s:%d:%d: %s" severity d.file d.line d.column
              d.message)
          diagnostics
      in

      let full_text = String.concat "\n" (status_text :: diagnostic_texts) in
      Ok
        {
          Mcp.Request.Tools.Call.content =
            [
              Mcp.Types.Content.Text
                { Mcp.Types.Content.type_ = "text"; text = full_text };
            ];
          is_error = None;
          structured_content = None;
        }

let format_signature_item item =
  let rec format = function
    | Merlin_client.Value (name, typ) -> Printf.sprintf "val %s : %s" name typ
    | Merlin_client.Type (name, def) -> Printf.sprintf "type %s = %s" name def
    | Merlin_client.Exception (name, typ) ->
        Printf.sprintf "exception %s of %s" name typ
    | Merlin_client.Module (name, contents) ->
        let content_str = String.concat "\n  " (List.map format contents) in
        Printf.sprintf "module %s : sig\n  %s\nend" name content_str
  in
  format item

let handle_module_signature merlin args _ctx =
  match merlin with
  | None ->
      Ok
        {
          Mcp.Request.Tools.Call.content =
            [
              Mcp.Types.Content.Text
                {
                  Mcp.Types.Content.type_ = "text";
                  text =
                    "Merlin not available. Please ensure merlin is installed \
                     and configured for your project.";
                };
            ];
          is_error = Some true;
          structured_content = None;
        }
  | Some merlin_client ->
      let signature =
        Merlin_client.get_module_signature merlin_client
          ~module_path:args.module_path
      in
      let formatted =
        String.concat "\n" (List.map format_signature_item signature)
      in
      Ok
        {
          Mcp.Request.Tools.Call.content =
            [
              Mcp.Types.Content.Text
                { Mcp.Types.Content.type_ = "text"; text = formatted };
            ];
          is_error = None;
          structured_content = None;
        }

let create_server ~sw ~env ~config =
  let project_root =
    match config.project_root with
    | Some root -> root
    | None -> Option.value (find_project_root ()) ~default:(Sys.getcwd ())
  in

  (* Initialize dune RPC if enabled *)
  let dune_rpc =
    if config.enable_dune && Sys.getenv_opt "OCAML_MCP_NO_DUNE" = None then (
      Mcp_eio.Logging.debug "Initializing Dune RPC client";
      let client = Dune_rpc_client.create ~sw ~env ~root:project_root in
      (* Start polling in background *)
      Fiber.fork ~sw (fun () ->
          Mcp_eio.Logging.debug "Starting Dune RPC polling loop";
          Dune_rpc_client.run client);
      Some client)
    else (
      Mcp_eio.Logging.debug "Dune RPC disabled";
      None)
  in

  (* Initialize merlin if enabled *)
  let merlin =
    if config.enable_merlin then
      try
        Some
          (Merlin_client.create ~sw
             ~mgr:(Eio.Stdenv.process_mgr env)
             ~project_root)
      with _ -> None
    else None
  in

  (* Create SDK server *)
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
      ()
  in

  (* Register tools *)
  Server.tool server "dune/build-status"
    ~description:
      "Get the current build status from dune, including any errors or warnings"
    ~args:
      (module struct
        type t = build_status_args

        let to_yojson = build_status_args_to_yojson
        let of_yojson = build_status_args_of_yojson

        let schema () =
          `Assoc
            [
              ("type", `String "object");
              ( "properties",
                `Assoc
                  [
                    ( "targets",
                      `Assoc
                        [
                          ("type", `String "array");
                          ("items", `Assoc [ ("type", `String "string") ]);
                        ] );
                  ] );
              ("required", `List []);
            ]
      end)
    (handle_build_status dune_rpc);

  Server.tool server "ocaml/module-signature"
    ~description:"Get the signature of an OCaml module using merlin"
    ~args:
      (module struct
        type t = module_signature_args

        let to_yojson = module_signature_args_to_yojson
        let of_yojson = module_signature_args_of_yojson

        let schema () =
          `Assoc
            [
              ("type", `String "object");
              ( "properties",
                `Assoc
                  [
                    ( "module_path",
                      `Assoc
                        [
                          ("type", `String "array");
                          ("items", `Assoc [ ("type", `String "string") ]);
                        ] );
                  ] );
              ("required", `List [ `String "module_path" ]);
            ]
      end)
    (handle_module_signature merlin);

  server

let run ~sw ~env ~connection ~config =
  Mcp_eio.Logging.info "Starting OCaml MCP Server";
  let server = create_server ~sw ~env ~config in
  let mcp_server = Server.to_mcp_server server in
  Mcp_eio.Connection.serve ~sw connection mcp_server

let run_stdio ~env ~config =
  Mcp_eio.Logging.info "Starting MCP server in stdio mode";
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
  Mcp_eio.Logging.info "Server run completed, exiting switch"
