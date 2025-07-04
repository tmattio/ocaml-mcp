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
  - Logging

List tools:
  $ mcp-client --socket 8080 list tools
  Tools (10):
  - fs/write: Write content to a file. For OCaml files (.ml/.mli), automatically formats the code and returns diagnostics.
  - dune/build-status: Get the current build status from dune, including any errors or warnings
  - ocaml/find-references: Find all usages of a symbol
  - dune/run-tests: Execute tests and report results
  - fs/edit: Replace text within a file. For OCaml files (.ml/.mli), automatically formats the result and returns diagnostics.
  - ocaml/module-signature: Get the signature of an OCaml module from build artifacts
  - ocaml/find-definition: Find where a symbol is defined
  - dune/build-target: Build specific files/libraries/tests
  - ocaml/project-structure: Return project layout, libraries, executables
  - ocaml/eval: Evaluate OCaml expressions in project context

Kill the server:
  $ kill $SERVER_PID 2>/dev/null
