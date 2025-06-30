Test OCaml MCP Server tools functionality using mcp-client

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock --no-dune &
  $ SERVER_PID=$!

Test server info:
  $ mcp-client --pipe test.sock info
  Server: ocaml-mcp-server v0.1.0
  
  Capabilities:
  - Tools

List available tools:
  $ mcp-client --pipe test.sock list tools
  Tools (2):
  - dune/build-status: Get the current build status from dune, including any errors or warnings
  - ocaml/module-signature: Get the signature of an OCaml module from build artifacts

Test calling ocaml/module-signature tool with List module:
  $ mcp-client --pipe test.sock call ocaml/module-signature -a '{"module_path":["List"]}'
  Could not find module List in _build/_private/.pkg/. Make sure the project is built with dune.

Test calling non-existent tool:
  $ mcp-client --pipe test.sock call nonexistent/tool 2>&1 | head -1
  Fatal error: exception Failure("Request failed: JSON-RPC error")

Test with invalid arguments for module-signature:
  $ mcp-client --pipe test.sock call ocaml/module-signature -a '{"wrong_field":"value"}' 2>&1 | head -1
  Fatal error: exception Failure("Request failed: JSON-RPC error")

Test with empty module path:
  $ mcp-client --pipe test.sock call ocaml/module-signature -a '{"module_path":[]}' 
  Could not find module  in _build/_private/.pkg/. Make sure the project is built with dune.

Kill the server
  $ kill $SERVER_PID 2>/dev/null
