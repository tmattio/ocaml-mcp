Test OCaml eval tool functionality

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock --no-dune &
  $ SERVER_PID=$!

Test evaluating a simple expression:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"1 + 1"}'
  - : int = 2

Test evaluating a let binding:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"let x = 42"}'
  val x : int = 42

Test evaluating an expression using the previous binding:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"x * 2"}'
  - : int = 84

Test evaluating a function definition:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"let double x = x * 2"}'
  val double : int -> int = <fun>

Test calling the function:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"double 21"}'
  - : int = 42

Test evaluating invalid code:
  $ mcp-client --pipe test.sock call ocaml/eval -a '{"code":"let x ="}'
  Error: Syntax error: File "", line 1, characters 7-9:
  Error: Syntax error

Kill the server
  $ kill $SERVER_PID 2>/dev/null