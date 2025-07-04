Test OCaml MCP Server build-target tool

Start dune RPC and MCP server:

  $ dune build --watch --root "$PWD/test_project" &
  Entering directory 'test_project'
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Test passed
  Success, waiting for filesystem changes...
  Error: Don't know how to build nonexistent.exe
  Had 1 error, waiting for filesystem changes...
  $ DUNE_PID=$!
  $ ocaml-mcp-server --pipe test.sock --root "$PWD/test_project" -vv &
  ocaml-mcp-server: [INFO] Listening on unix:test.sock
  ocaml-mcp-server: [INFO] Server ready, waiting for connections...
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Initializing Dune RPC client
  ocaml-mcp-server: [DEBUG] Starting Dune RPC polling loop
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool dune/build-target executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Test building the library:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["lib/mylib.cma"]}'
  Building targets: lib/mylib.cma
  Success

Test building the executable:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["bin/main.exe"]}'
  Building targets: bin/main.exe
  Success

Test building multiple targets:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["lib/mylib.cma", "bin/main.exe"]}'
  Building targets: lib/mylib.cma bin/main.exe
  Success

Test building all:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["@all"]}'
  Building targets: @all
  Success

Test building the test:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["@test/runtest"]}'
  Building targets: @test/runtest
  Success

Test building a non-existent target:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["nonexistent.exe"]}'
  Building targets: nonexistent.exe
  Error: Don't know how to build nonexistent.exe
  Error: Build failed with 1 error.

Clean up:

  $ kill $SERVER_PID 2>/dev/null
  $ kill -9 $DUNE_PID 2>/dev/null
