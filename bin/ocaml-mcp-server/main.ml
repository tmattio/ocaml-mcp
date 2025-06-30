(** OCaml MCP Server executable *)

open Eio_main
open Cmdliner

(** Transport configuration *)
type transport_config = Stdio | Socket of int | Pipe of string

let setup_logging style_renderer level =
  (* Setup Logs reporter *)
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level level

let handle_client ~sw ~env ~config connection =
  (* Run the server for this connection *)
  Ocaml_mcp_server.run ~sw ~env ~connection ~config

let accept_loop ~env ~sw ~config ~net addr =
  let listening_socket =
    Eio.Net.listen ~sw ~backlog:5 ~reuse_addr:true net addr
  in
  Logs.info (fun m -> m "Listening on %a" Eio.Net.Sockaddr.pp addr);
  Logs.info (fun m -> m "Server ready, waiting for connections...");
  (* Accept connections in a loop *)
  while true do
    let socket, client_addr = Eio.Net.accept ~sw listening_socket in
    Logs.info (fun m ->
        m "Accepted connection from %a" Eio.Net.Sockaddr.pp client_addr);
    (* Handle each client in a new fiber *)
    Eio.Fiber.fork ~sw (fun () ->
        try
          let transport = Mcp_eio.Socket.create_from_socket socket in
          let connection =
            Mcp_eio.Connection.create (module Mcp_eio.Socket) transport
          in
          handle_client ~sw ~env ~config connection;
          Logs.info (fun m ->
              m "Client disconnected: %a" Eio.Net.Sockaddr.pp client_addr)
        with exn ->
          (* Log error but don't crash the server *)
          Logs.err (fun m ->
              m "Client error (%a): %s" Eio.Net.Sockaddr.pp client_addr
                (Printexc.to_string exn)))
  done

let run_server config transport_config () =
  run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  match transport_config with
  | Stdio ->
      (* For stdio, handle single connection *)
      Logs.info (fun m -> m "Running in stdio mode");
      let stdin = Eio.Stdenv.stdin env in
      let stdout = Eio.Stdenv.stdout env in
      let transport = Mcp_eio.Stdio.create ~stdin ~stdout in
      let connection =
        Mcp_eio.Connection.create (module Mcp_eio.Stdio) transport
      in
      handle_client ~sw ~env ~config connection
  | Socket port ->
      (* For socket, accept multiple connections *)
      let net = Eio.Stdenv.net env in
      let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
      accept_loop ~env ~sw ~config ~net addr
  | Pipe path ->
      (* For pipe, accept multiple connections *)
      let net = Eio.Stdenv.net env in
      let addr = `Unix path in
      (* Ensure socket file is cleaned up on exit *)
      Eio.Switch.on_release sw (fun () ->
          try Unix.unlink path with Unix.Unix_error _ -> ());
      accept_loop ~env ~sw ~config ~net addr

(* Command-line arguments *)

let project_root =
  let doc =
    "Project root directory. If not specified, will try to auto-detect."
  in
  Arg.(value & opt (some dir) None & info [ "root" ] ~docv:"DIR" ~doc)

let enable_dune =
  let doc = "Enable Dune RPC integration for build status and diagnostics." in
  Arg.(value & flag & info [ "dune" ] ~doc)

let no_dune =
  let doc = "Disable Dune RPC integration." in
  Arg.(value & flag & info [ "no-dune" ] ~doc)

let socket_port =
  let doc = "Listen on TCP port for connections." in
  Arg.(value & opt (some int) None & info [ "socket" ] ~docv:"PORT" ~doc)

let pipe_path =
  let doc = "Listen on Unix domain socket for connections." in
  Arg.(value & opt (some string) None & info [ "pipe" ] ~docv:"PATH" ~doc)

let stdio =
  let doc = "Use stdin/stdout for communication (default)." in
  Arg.(value & flag & info [ "stdio" ] ~doc)

let setup_log =
  let docs = Manpage.s_common_options in
  Term.(
    const setup_logging
    $ Fmt_cli.style_renderer ~docs ()
    $ Logs_cli.level ~docs ())

let parse_transport stdio socket_port pipe_path =
  match (stdio, socket_port, pipe_path) with
  | _, Some port, _ -> Socket port
  | _, _, Some path -> Pipe path
  | _ -> Stdio

let parse_dune_config enable_dune no_dune =
  match (enable_dune, no_dune) with
  | _, true -> false
  | true, _ -> true
  | _ -> true (* Default: enabled *)

let server_cmd =
  let doc = "OCaml MCP Server - provides tools for OCaml development" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "ocaml-mcp-server is a Model Context Protocol (MCP) server that \
         provides tools for OCaml development, including module signature \
         inspection and Dune build status integration.";
      `S "TRANSPORT MODES";
      `P "The server supports three transport modes:";
      `I ("stdio", "Use standard input/output for communication (default)");
      `I ("socket", "Listen on a TCP port for connections");
      `I ("pipe", "Listen on a Unix domain socket for connections");
      `S "AVAILABLE TOOLS";
      `P "The server provides the following MCP tools:";
      `I
        ( "dune/build-status",
          "Get current build status from dune, including errors and warnings" );
      `I
        ( "ocaml/module-signature",
          "Get the signature of an OCaml module from build artifacts" );
      `S "ENVIRONMENT VARIABLES";
      `I
        ( "$(b,MCP_DEBUG)",
          "Enable debug logging (equivalent to $(b,--verbosity=debug))" );
      `I ("$(b,OCAML_MCP_NO_DUNE)", "Disable Dune RPC integration");
      `S Manpage.s_bugs;
      `P "Report bugs at https://github.com/YOUR-GITHUB/ocaml-mcp/issues";
    ]
  in
  let info = Cmd.info "ocaml-mcp-server" ~version:"0.1.0" ~doc ~man in
  let term =
    Term.(
      const
        (fun
          setup_log
          project_root
          stdio
          socket_port
          pipe_path
          enable_dune
          no_dune
        ->
          setup_log;
          let transport = parse_transport stdio socket_port pipe_path in
          let enable_dune = parse_dune_config enable_dune no_dune in
          let config = Ocaml_mcp_server.{ project_root; enable_dune } in
          run_server config transport ())
      $ setup_log $ project_root $ stdio $ socket_port $ pipe_path $ enable_dune
      $ no_dune)
  in
  Cmd.v info term

let () =
  (* Check for MCP_DEBUG environment variable *)
  (match Sys.getenv_opt "MCP_DEBUG" with
  | Some _ -> Logs.set_level (Some Logs.Debug)
  | None -> ());
  exit (Cmd.eval server_cmd)
