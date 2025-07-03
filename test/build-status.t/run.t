Test OCaml MCP Server dune RPC functionality

Create a simple dune project:

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > (name test_project)
  > EOF
  $ cat > dune << EOF
  > (executable
  >  (name main))
  > EOF
  $ cat > main.ml << EOF
  > let () = print_endline "Hello from test project"
  > EOF

Start dune RPC and MCP server:

  $ dune build --watch --root . &
  Success, waiting for filesystem changes...
  $ DUNE_PID=$!
  $ ocaml-mcp-server --pipe test.sock -vv &
  ocaml-mcp-server: [INFO] Listening on unix:test.sock
  ocaml-mcp-server: [INFO] Server ready, waiting for connections...
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-status executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

  $ mcp-client --pipe test.sock call dune/build-status
  Build waiting...

Clean up:

  $ kill $SERVER_PID 2>/dev/null
  $ kill -9 $DUNE_PID 2>/dev/null
  $ rm -f dune-project dune main.ml
