Test OCaml eval tool functionality

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock --no-dune -vv &
  ocaml-mcp-server: [INFO] Listening on unix:test.sock
  ocaml-mcp-server: [INFO] Server ready, waiting for connections...
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/call (id: 1)
  ocaml-mcp-server: [INFO] Tool ocaml/eval executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Test evaluating a simple expression:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"1 + 1"}'
  - : int = 2

Test evaluating a let binding:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"let x = 42"}'
  val x : int = 42

Test evaluating an expression using the previous binding:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"x * 2"}'
  - : int = 84

Test evaluating a function definition:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"let double x = x * 2"}'
  val double : int -> int = <fun>

Test calling the function:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"double 21"}'
  - : int = 42

Test evaluating invalid code:
  $ mcp --pipe test.sock call ocaml/eval -a '{"code":"let x ="}'
  File "_none_", line 1, characters 7-9:
  Error: Syntax error

Kill the server
  $ kill $SERVER_PID 2>/dev/null
