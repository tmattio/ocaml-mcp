(** OCaml MCP Server executable *)

open Eio_main

(** Transport configuration *)
type transport_config = Stdio | Socket of int | Pipe of string

let connect_transport ~env ~sw config =
  match config with
  | Stdio ->
      (* Use stdin/stdout of the current process *)
      let stdin = Eio.Stdenv.stdin env in
      let stdout = Eio.Stdenv.stdout env in
      let transport = Mcp_eio.Stdio.create ~stdin ~stdout in
      Mcp_eio.Connection.create (module Mcp_eio.Stdio) transport
  | Socket port ->
      (* Listen on TCP socket *)
      let net = Eio.Stdenv.net env in
      let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
      let transport = Mcp_eio.Socket.create_server ~net ~sw addr in
      Mcp_eio.Connection.create (module Mcp_eio.Socket) transport
  | Pipe path ->
      (* Listen on Unix domain socket *)
      let net = Eio.Stdenv.net env in
      let addr = `Unix path in
      let transport = Mcp_eio.Socket.create_server ~net ~sw addr in
      Mcp_eio.Connection.create (module Mcp_eio.Socket) transport

let run_server config transport_config =
  run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  (* Create connection based on configuration *)
  let connection = connect_transport ~env ~sw transport_config in

  (* Run the server *)
  Ocaml_mcp_server.run ~sw ~env ~connection ~config

(* Simple CLI argument parsing *)

let print_usage () =
  Printf.printf "OCaml MCP Server - provides tools for OCaml development\n\n";
  Printf.printf "Usage: ocaml-mcp-server [OPTIONS]\n\n";
  Printf.printf "Options:\n";
  Printf.printf "  --socket <port>     Listen on TCP port\n";
  Printf.printf "  --pipe <path>       Listen on Unix socket\n";
  Printf.printf "  --stdio             Use stdin/stdout (default)\n";
  Printf.printf "  --root <dir>        Project root directory\n";
  Printf.printf "  --dune              Enable dune RPC (default)\n";
  Printf.printf "  --no-dune           Disable dune RPC\n";
  Printf.printf "  --merlin            Enable merlin (default)\n";
  Printf.printf "  --no-merlin         Disable merlin\n";
  Printf.printf "\nAvailable tools:\n";
  Printf.printf "  dune/build-status       Get current build status from dune\n";
  Printf.printf "  ocaml/module-signature  Get module signatures using merlin\n";
  exit 1

let parse_args args =
  let transport = ref Stdio in
  let project_root = ref None in
  let enable_dune = ref true in
  let enable_merlin = ref true in

  let rec parse = function
    | [] -> ()
    | "--socket" :: port :: rest ->
        transport := Socket (int_of_string port);
        parse rest
    | "--pipe" :: path :: rest ->
        transport := Pipe path;
        parse rest
    | "--stdio" :: rest ->
        transport := Stdio;
        parse rest
    | "--root" :: dir :: rest ->
        project_root := Some dir;
        parse rest
    | "--dune" :: rest ->
        enable_dune := true;
        parse rest
    | "--no-dune" :: rest ->
        enable_dune := false;
        parse rest
    | "--merlin" :: rest ->
        enable_merlin := true;
        parse rest
    | "--no-merlin" :: rest ->
        enable_merlin := false;
        parse rest
    | _ -> print_usage ()
  in

  parse args;

  let config =
    Ocaml_mcp_server.
      {
        project_root = !project_root;
        enable_dune = !enable_dune;
        enable_merlin = !enable_merlin;
      }
  in

  (config, !transport)

let () =
  (* Enable debug logging if MCP_DEBUG is set *)
  if Sys.getenv_opt "MCP_DEBUG" <> None then Mcp_eio.Logging.set_level Debug;

  let args = List.tl (Array.to_list Sys.argv) in
  let config, transport = parse_args args in
  run_server config transport
