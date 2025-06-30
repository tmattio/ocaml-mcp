Test OCaml MCP Server via HTTP transport

Start the HTTP server:
  $ ocaml-mcp-server --socket 8080 --no-dune &
  $ SERVER_PID=$!
  $ sleep 1

Test server info:
  $ mcp-client --socket 8080 info
  Server: ocaml-mcp-server v0.1.0
  
  Capabilities:
  - Tools

List tools:
  $ mcp-client --socket 8080 list tools
  Tools (2):
  - dune/build-status: Get the current build status from dune, including any errors or warnings
  - ocaml/module-signature: Get the signature of an OCaml module from build artifacts

Kill the server:
  $ kill $SERVER_PID 2>/dev/null
