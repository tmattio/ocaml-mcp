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

First build the project:

  $ dune build

Start dune build in watch mode to enable RPC:

  $ dune build --watch > /dev/null 2>&1 &
  $ DUNE_PID=$!
  $ sleep 1

Start MCP server and test build status:

  $ ocaml-mcp-server --pipe test.sock &
  $ SERVER_PID=$!
  $ sleep 1

  $ mcp-client --pipe test.sock call dune/build-status
  Build waiting...

Clean up:

  $ kill $SERVER_PID 2>/dev/null
  $ kill $DUNE_PID 2>/dev/null
  $ rm -f dune-project dune main.ml
