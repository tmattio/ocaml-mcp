Test filesystem tools (read, write, edit) functionality

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock --no-dune &
  $ SERVER_PID=$!

Create a test directory structure
  $ mkdir -p test_project
  $ cd test_project

Basic fs/write - Create a simple OCaml file:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"hello.ml","content":"let greeting = \"Hello, world!\"\nlet () = print_endline greeting"}'
  {
    "file_path": "hello.ml",
    "format_result": "Code formatted successfully"
  }

Verify the file was created:
  $ cat hello.ml
  let greeting = "Hello, world!"
  let () = print_endline greeting

Basic fs/read - Read the file back:
  $ mcp-client --pipe ../test.sock call fs/read -a '{"file_path":"hello.ml"}'
  {
    "content": "let greeting = \"Hello, world!\"\nlet () = print_endline greeting",
    "file_type": "ocaml"
  }

Basic fs/edit - Modify the greeting:
  $ mcp-client --pipe ../test.sock call fs/edit -a '{"file_path":"hello.ml","old_string":"\"Hello, world!\"","new_string":"\"Hello, OCaml!\""}'
  {
    "file_path": "hello.ml",
    "format_result": "Code formatted successfully"
  }

Verify the edit:
  $ cat hello.ml
  let greeting = "Hello, OCaml!"
  let () = print_endline greeting

Test automatic formatting with fs/write:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"unformatted.ml","content":"let    x=1+2\n  let y  =   3"}' 2>&1 | grep -q "format_result" && echo "Formatting attempted"
  Formatting attempted

Test fs/write with modules:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"module.ml","content":"module M = struct\n  let value = 42\nend"}'
  {
    "file_path": "module.ml",
    "format_result": "Code formatted successfully"
  }

Test different OCaml file extensions (.mli):
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"interface.mli","content":"val compute : int -> int"}'
  {
    "file_path": "interface.mli",
    "format_result": "Code formatted successfully"
  }

  $ mcp-client --pipe ../test.sock call fs/read -a '{"file_path":"interface.mli"}' 2>&1 | grep "file_type"
    "file_type": "ocaml"

Test fs/write with a non-OCaml file:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"README.md","content":"# Test Project\n\nThis is a test."}'
  {
    "file_path": "README.md"
  }

Test fs/read on non-OCaml file:
  $ mcp-client --pipe ../test.sock call fs/read -a '{"file_path":"README.md"}'
  {
    "content": "# Test Project\n\nThis is a test.",
    "file_type": "other"
  }

Test fs/edit with non-existent file:
  $ mcp-client --pipe ../test.sock call fs/edit -a '{"file_path":"nonexistent.ml","old_string":"foo","new_string":"bar"}' 2>&1 | grep -o "File not found"
  File not found

Test fs/read with non-existent file:
  $ mcp-client --pipe ../test.sock call fs/read -a '{"file_path":"nonexistent.ml"}' 2>&1 | grep -o "File not found"
  File not found

Test fs/write with invalid OCaml code (should still write but report issues):
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"bad.ml","content":"let x = "}' 2>&1 | grep -q "file_path" && echo "File written despite syntax error"
  File written despite syntax error

Test fs/edit with replace_all option:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"multi.ml","content":"let x = 1\nlet y = 1\nlet z = 1"}'
  {
    "file_path": "multi.ml",
    "format_result": "Code formatted successfully"
  }

  $ mcp-client --pipe ../test.sock call fs/edit -a '{"file_path":"multi.ml","old_string":"1","new_string":"42","replace_all":true}'
  {
    "file_path": "multi.ml",
    "format_result": "Code formatted successfully"
  }

  $ cat multi.ml
  let x = 42
  let y = 42
  let z = 42

Test fs/edit preserving OCaml structure:
  $ mcp-client --pipe ../test.sock call fs/write -a '{"file_path":"func.ml","content":"let add x y = x + y\nlet multiply x y = x * y"}'
  {
    "file_path": "func.ml",
    "format_result": "Code formatted successfully"
  }

  $ mcp-client --pipe ../test.sock call fs/edit -a '{"file_path":"func.ml","old_string":"add","new_string":"sum"}'
  {
    "file_path": "func.ml",
    "format_result": "Code formatted successfully"
  }

  $ cat func.ml
  let sum x y = x + y
  let multiply x y = x * y

Clean up
  $ cd ..
  $ rm -rf test_project

Kill the server
  $ kill $SERVER_PID 2>/dev/null