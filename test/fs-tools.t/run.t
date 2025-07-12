Test filesystem tools (read, write, edit) functionality

Create a test directory structure
  $ mkdir -p test_project
  $ cd test_project

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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_read executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_edit executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_read executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_read executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_edit executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_read executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_edit executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_write executed successfully
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
  ocaml-mcp-server: [INFO] Tool fs_edit executed successfully
  ocaml-mcp-server: [DEBUG] Sending response
  ocaml-mcp-server: [INFO] Client disconnected
  ocaml-mcp-server: [DEBUG] Server loop ended
  $ SERVER_PID=$!
  $ sleep 1

Basic fs_write - Create a simple OCaml file:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"hello.ml","content":"let greeting = \"Hello, world!\"\nlet () = print_endline greeting"}'
  Wrote ./hello.ml (formatted, no diagnostics)

Verify the file was created:
  $ cat hello.ml
  let greeting = "Hello, world!"
  let () = print_endline greeting

Basic fs_read - Read the file back:
  $ mcp --pipe test.sock call fs_read -a '{"file_path":"hello.ml"}'
  Read ./hello.ml (no diagnostics)

Basic fs_edit - Modify the greeting:
  $ mcp --pipe test.sock call fs_edit -a '{"file_path":"hello.ml","old_string":"\"Hello, world!\"","new_string":"\"Hello, OCaml!\""}'
  Edited ./hello.ml (1 replacements, formatted, no diagnostics)

Verify the edit:
  $ cat hello.ml
  let greeting = "Hello, OCaml!"
  let () = print_endline greeting

Test automatic formatting with fs_write:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"unformatted.ml","content":"let    x=1+2\n  let y  =   3"}' 2>&1 | grep -q "format_result" && echo "Formatting attempted"
  [1]

Test fs_write with modules:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"module.ml","content":"module M = struct\n  let value = 42\nend"}'
  Wrote ./module.ml (formatted, no diagnostics)

Test different OCaml file extensions (.mli):
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"interface.mli","content":"val compute : int -> int"}'
  Wrote ./interface.mli (formatted, 1 diagnostics)

  $ mcp --pipe test.sock call fs_read -a '{"file_path":"interface.mli"}' 2>&1 | grep "file_type"
  [1]

Test fs_write with a non-OCaml file:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"README.md","content":"# Test Project\n\nThis is a test."}'
  Successfully wrote to ./README.md

Test fs_read on non-OCaml file:
  $ mcp --pipe test.sock call fs_read -a '{"file_path":"README.md"}'
  # Test Project

  This is a test.

Test fs_edit with non-existent file:
  $ mcp --pipe test.sock call fs_edit -a '{"file_path":"nonexistent.ml","old_string":"foo","new_string":"bar"}' 2>&1 | grep -o "File not found"
  File not found

Test fs_read with non-existent file:
  $ mcp --pipe test.sock call fs_read -a '{"file_path":"nonexistent.ml"}' 2>&1 | grep -o "File not found"
  File not found

Test fs_write with invalid OCaml code (should still write but report issues):
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"bad.ml","content":"let x = "}' 2>&1 | grep -q "file_path" && echo "File written despite syntax error"
  [1]

Test fs_edit with replace_all option:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"multi.ml","content":"let x = 1\nlet y = 1\nlet z = 1"}'
  Wrote ./multi.ml (formatted, no diagnostics)

  $ mcp --pipe test.sock call fs_edit -a '{"file_path":"multi.ml","old_string":"1","new_string":"42","replace_all":true}'
  Edited ./multi.ml (3 replacements, formatted, no diagnostics)

  $ cat multi.ml
  let x = 42
  let y = 42
  let z = 42

Test fs_edit preserving OCaml structure:
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"func.ml","content":"let add x y = x + y\nlet multiply x y = x * y"}'
  Wrote ./func.ml (formatted, no diagnostics)

  $ mcp --pipe test.sock call fs_edit -a '{"file_path":"func.ml","old_string":"add","new_string":"sum"}'
  Edited ./func.ml (1 replacements, formatted, no diagnostics)

  $ cat func.ml
  let sum x y = x + y
  let multiply x y = x * y

Clean up and kill the server
  $ cd ..
  $ rm -rf test_project
  $ kill $SERVER_PID 2>/dev/null || true
