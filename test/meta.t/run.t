Test _meta field support in OCaml MCP Server

Start the MCP server in the background
  $ ocaml-mcp-server --pipe test.sock &
  $ SERVER_PID=$!
  $ sleep 1

Test 1: Tool call without metadata
  $ mcp --pipe test.sock call fs_write -a '{"file_path":"/tmp/test.txt","content":"hello"}'
  {"path":"/tmp/test.txt","formatted":false,"diagnostics":null}

Test 2: Tool call with valid metadata
  $ mcp --pipe test.sock --meta '{"client/id":"test-123","debug.enabled":true}' call fs_write -a '{"file_path":"/tmp/test-meta.txt","content":"hello"}' 
  {"path":"/tmp/test-meta.txt","formatted":false,"diagnostics":null}

Test 3: Tool call with invalid metadata (reserved prefix)
  $ mcp --pipe test.sock --meta '{"mcp.dev/internal":"value"}' call fs_write -a '{"file_path":"/tmp/test-bad.txt","content":"hello"}'  2>&1 | head -1
  Invalid meta JSON: Using a reserved MCP prefix is not allowed: 'mcp.dev/internal'

Test 4: Tool call with single-character prefix (should work)
  $ mcp --pipe test.sock --meta '{"x/feature":"enabled"}' call fs_write -a '{"file_path":"/tmp/test-single.txt","content":"hello"}'
  {"path":"/tmp/test-single.txt","formatted":false,"diagnostics":null}

Test 5: List tools with metadata
  $ mcp --pipe test.sock --meta '{"client/version":"2.0"}' list tools | grep -c "fs_write"
  1

Test 6: List resources with metadata
  $ mcp --pipe test.sock --meta '{"client/scope":"test"}' list resources | head -1
  Resources (0):

Kill the server and clean up
  $ kill $SERVER_PID 2>/dev/null
  $ rm -f /tmp/test.txt /tmp/test-meta.txt /tmp/test-single.txt
