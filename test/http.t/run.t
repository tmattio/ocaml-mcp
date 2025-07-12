Test OCaml MCP Server via HTTP transport

Start the HTTP server:
  $ ocaml-mcp-server --socket 8080 --no-dune &
  $ SERVER_PID=$!
  $ sleep 1

Test server info:
  $ mcp --socket 8080 info
  Server: ocaml-mcp-server v0.1.0

  Capabilities:
  - Tools
  - Logging

List tools:
  $ mcp --socket 8080 list tools
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

Kill the server:
  $ kill $SERVER_PID 2>/dev/null
