Test OCaml MCP Server build-target tool

Navigate to the test project:
  $ cd test_project

Start dune build in watch mode to enable RPC:

  $ dune build --watch --root . >/dev/null 2>&1 &
  $ DUNE_PID=$!
  $ sleep 1

Start MCP server:

  $ ocaml-mcp-server --pipe test.sock &
  $ SERVER_PID=$!
  $ sleep 1

Test building the library:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["lib/mylib.cma"]}'
  Building targets: lib/mylib.cma
  Success

Test building the executable:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["bin/main.exe"]}'
  Building targets: bin/main.exe
  Success

Test building multiple targets:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["lib/mylib.cma", "bin/main.exe"]}'
  Building targets: lib/mylib.cma bin/main.exe
  Success

Test building all:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["@all"]}'
  Building targets: @all
  Success

Test building the test:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["@test/runtest"]}'
  Building targets: @test/runtest
  Success

Test building a non-existent target:

  $ mcp-client --pipe test.sock call dune/build-target -a '{"targets":["nonexistent.exe"]}'
  Building targets: nonexistent.exe
  Error: Don't know how to build nonexistent.exe
  Error: Build failed with 1 error.

Clean up:

  $ kill $SERVER_PID 2>/dev/null
  $ kill $DUNE_PID 2>/dev/null
