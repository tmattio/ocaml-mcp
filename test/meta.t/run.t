Test _meta field support in OCaml MCP Server

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock &
  $ SERVER_PID=$!
  $ sleep 1

Test 1: Tool call without metadata
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"/tmp/test.txt","content":"hello"}'
  {"path":"/tmp/test.txt","formatted":false,"diagnostics":null}

Test 2: Tool call with valid metadata
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"/tmp/test-meta.txt","content":"hello"}' --meta '{"client/id":"test-123","debug.enabled":true}'
  {"path":"/tmp/test-meta.txt","formatted":false,"diagnostics":null}

Test 3: Tool call with invalid metadata (reserved prefix)
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"/tmp/test-bad.txt","content":"hello"}' --meta '{"mcp.dev/internal":"value"}' 2>&1 | head -1
  Fatal error: exception Failure("Request failed: JSON-RPC error")

Test 4: Tool call with single-character prefix (should work)
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"/tmp/test-single.txt","content":"hello"}' --meta '{"x/feature":"enabled"}'
  {"path":"/tmp/test-single.txt","formatted":false,"diagnostics":null}

Test 5: List tools with metadata
  $ mcp --pipe test.sock list tools --meta '{"client/version":"2.0"}' | grep -c "fs_write"
  1

Test 6: List resources with metadata
  $ mcp --pipe test.sock list resources --meta '{"client/scope":"test"}' | head -1
  Resources (0):

Kill the server and clean up
  $ kill $SERVER_PID 2>/dev/null
  $ rm -f /tmp/test.txt /tmp/test-meta.txt /tmp/test-single.txt
