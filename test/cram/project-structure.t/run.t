Test project-structure tool

Start the MCP server for the test project:
  $ ocaml-mcp-server --pipe test.sock --no-dune --root "$PWD/test_project" -vv &
  ocaml-mcp-server: [INFO] Listening on unix:test.sock
  ocaml-mcp-server: [INFO] Server ready, waiting for connections...
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server (async)
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [ERROR] Tool ocaml_project_structure failed: Failed to parse arguments: Project_structure.Args.t
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Test calling project-structure tool (no args needed):
  $ mcp --pipe test.sock call ocaml_project_structure
  Fatal error: exception Failure("Request failed: JSON-RPC error")
  [2]

Kill the server:
  $ kill $SERVER_PID 2>/dev/null
