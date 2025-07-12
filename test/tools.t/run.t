Test OCaml MCP Server tools functionality using mcp

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
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  ocaml-mcp-server: [INFO] Accepted connection from unix:
  ocaml-mcp-server: [INFO] Starting OCaml MCP Server
  ocaml-mcp-server: [DEBUG] Dune RPC disabled
  ocaml-mcp-server: [DEBUG] Registering project-structure tool with project_root: .
  ocaml-mcp-server: [INFO] MCP logging enabled
  ocaml-mcp-server: [INFO] Received request: initialize (id: 0)
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Received request: tools/list (id: 1)
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
  ocaml-mcp-server: [DEBUG] handle_module_signature called with module_path: List
  ocaml-mcp-server: [INFO] Tool ocaml_module_signature executed successfully
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
  ocaml-mcp-server: [ERROR] Unknown tool: nonexistent/tool
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
  ocaml-mcp-server: [ERROR] Tool ocaml_module_signature failed: Input validation failed: jsonschema validation failed with inline://schema
    at '': missing properties module_path
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
  ocaml-mcp-server: [DEBUG] handle_module_signature called with module_path:
  ocaml-mcp-server: [INFO] Tool ocaml_module_signature executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Test server info:
  $ mcp --pipe test.sock info
  Server: ocaml-mcp-server v0.1.0

  Capabilities:
  - Tools
  - Logging

List available tools:
  $ mcp --pipe test.sock list tools
  Tools (10):
  - fs_write: Write content to a file. For OCaml files (.ml/.mli), automatically formats the code and returns diagnostics.
  - dune_build_status: Get the current build status from dune, including any errors or warnings
  - ocaml_find_references: Find all usages of a symbol
  - dune_run_tests: Execute tests and report results
  - fs_edit: Replace text within a file. For OCaml files (.ml/.mli), automatically formats the result and returns diagnostics.
  - ocaml_module_signature: Get the signature of an OCaml module from build artifacts
  - ocaml_find_definition: Find where a symbol is defined
  - dune_build_target: Build specific files/libraries/tests
  - ocaml_project_structure: Return project layout, libraries, executables
  - ocaml_eval: Evaluate OCaml expressions in project context

Test calling ocaml_module_signature tool with List module:
  $ mcp --pipe test.sock call ocaml_module_signature -a '{"module_path":["List"]}'
  Could not find module List in build artifacts. Make sure the project is built with dune.

Test calling non-existent tool:
  $ mcp --pipe test.sock call nonexistent/tool 2>&1 | head -1
  Fatal error: exception Failure("Request failed: JSON-RPC error")

Test with invalid arguments for module-signature:
  $ mcp --pipe test.sock call ocaml_module_signature -a '{"wrong_field":"value"}' 2>&1 | head -1
  Fatal error: exception Failure("Request failed: JSON-RPC error")

Test with empty module path:
  $ mcp --pipe test.sock call ocaml_module_signature -a '{"module_path":[]}'
  Could not find module  in build artifacts. Make sure the project is built with dune.

Kill the server
  $ kill $SERVER_PID 2>/dev/null
