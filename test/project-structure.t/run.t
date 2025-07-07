Test project-structure tool

Start the MCP server for the test project:
  $ ocaml-mcp-server --pipe test.sock --no-dune --root "$PWD/test_project" -vv &
  ocaml-mcp-server: [INFO] Listening on unix:test.sock
  ocaml-mcp-server: [INFO] Server ready, waiting for connections...
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] project-structure tool called with project_root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [DEBUG] Running dune describe workspace
  ocaml-mcp-server: [DEBUG] Found root: $TESTCASE_ROOT/test_project
  ocaml-mcp-server: [DEBUG] Parsed 2 components
  ocaml-mcp-server: [INFO] Tool ocaml/project-structure executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Test calling project-structure tool (no args needed):
  $ mcp --pipe test.sock call ocaml/project-structure
  Project Root: $TESTCASE_ROOT/test_project
  Build Context: default

  COMPONENT: Executable
    Name: main
    Directory: bin
    Dependencies: mylib
    Action: Build: dune build bin/main.exe
    Action: Run: dune exec bin/main.exe

  COMPONENT: Library
    Name: mylib
    Directory: lib
    Public Modules: Mylib
    Action: Build: dune build @lib/all

Kill the server:
  $ kill $SERVER_PID 2>/dev/null
