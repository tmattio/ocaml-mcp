(** OCaml MCP Server implementation using the SDK *)

open Eio
open Mcp_sdk

(* Setup logging *)
let src = Logs.Src.create "ocaml-mcp-server" ~doc:"OCaml MCP Server logging"

module Log = (val Logs.src_log src : Logs.LOG)

type config = { project_root : string option; enable_dune : bool }

let default_config = { project_root = None; enable_dune = true }

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

(* Types for module signatures *)
(* Currently unused - would be used when implementing proper .cmi parsing
type signature_item =
  | Value of string * string
  | Type of string * string  
  | Exception of string * string
  | Module of string * signature_item list
[@@warning "-37"]
*)

(* Helper functions for tool implementations *)
let handle_build_status dune_rpc _args _ctx =
  match dune_rpc with
  | None ->
      Ok
        (Mcp_sdk.Tool_result.error
           "Dune RPC not connected. Please run this command from a dune \
            project.")
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
      Ok (Mcp_sdk.Tool_result.text full_text)

(* Currently unused - would be used when implementing proper .cmi parsing
let format_signature_item item =
  let rec format = function
    | Value (name, typ) -> Printf.sprintf "val %s : %s" name typ
    | Type (name, def) -> Printf.sprintf "type %s = %s" name def
    | Exception (name, typ) ->
        Printf.sprintf "exception %s of %s" name typ
    | Module (name, contents) ->
        let content_str = String.concat "\n  " (List.map format contents) in
        Printf.sprintf "module %s : sig\n  %s\nend" name content_str
  in
  format item
*)

(* Find .cmi file for a module in _build directory *)
let find_cmi_file ~project_root ~module_path =
  let module_name =
    match module_path with [] -> None | path -> Some (String.concat "." path)
  in
  match module_name with
  | None -> None
  | Some name ->
      let lowercase_name = String.lowercase_ascii name in
      let cmi_name = lowercase_name ^ ".cmi" in
      let build_dir = Filename.concat project_root "_build" in
      let private_pkg_dir = Filename.concat build_dir "_private/.pkg" in

      (* Search in _build/_private/.pkg/ *)
      let rec search_dir dir =
        if Sys.file_exists dir && Sys.is_directory dir then
          let entries = Sys.readdir dir in
          Array.fold_left
            (fun acc entry ->
              match acc with
              | Some _ -> acc
              | None ->
                  let path = Filename.concat dir entry in
                  if entry = cmi_name then Some path
                  else if Sys.is_directory path then search_dir path
                  else None)
            None entries
        else None
      in
      search_dir private_pkg_dir

(* Read module signature from .cmi file *)
let read_module_signature ~cmi_path =
  (* For now, return a simple message indicating where the .cmi file is *)
  (* In a real implementation, we would parse the .cmi file *)
  Printf.sprintf
    "Module interface file found at: %s\n\n\
     To read the actual signature, a .cmi parser would be needed."
    cmi_path

let handle_module_signature project_root args _ctx =
  Log.debug (fun m ->
      m "handle_module_signature called with module_path: %s"
        (String.concat "." args.module_path));

  match find_cmi_file ~project_root ~module_path:args.module_path with
  | None ->
      Ok
        (Mcp_sdk.Tool_result.error
           (Printf.sprintf
              "Could not find module %s in _build/_private/.pkg/. Make sure \
               the project is built with dune."
              (String.concat "." args.module_path)))
  | Some cmi_path ->
      Log.debug (fun m -> m "Found .cmi file at: %s" cmi_path);
      let signature_text = read_module_signature ~cmi_path in
      Ok (Mcp_sdk.Tool_result.text signature_text)

let create_server ~sw ~env ~config =
  let project_root =
    match config.project_root with
    | Some root -> root
    | None -> Option.value (find_project_root ()) ~default:(Sys.getcwd ())
  in

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
    ~description:"Get the signature of an OCaml module from build artifacts"
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
    (handle_module_signature project_root);

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
