Test OCaml MCP Server tools functionality via stdio

Initialize the server and list tools:

  $ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c '.result | {name: .serverInfo.name, tools: .capabilities.tools}'
  {"name":"ocaml-mcp-server","tools":{}}

List available tools:

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c 'select(.id == 2) | .result.tools[] | {name: .name, description: .description}'
  {"name":"dune/build-status","description":"Get the current build status from dune, including any errors or warnings"}
  {"name":"ocaml/module-signature","description":"Get the signature of an OCaml module using merlin"}

Test calling dune/build-status tool (without dune RPC):

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"dune/build-status"}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c 'select(.id == 2) | .result.content[0].text'
  "Dune RPC not connected. Please run this command from a dune project."

Test calling ocaml/module-signature tool with List module:

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ocaml/module-signature","arguments":{"module_path":["List"]}}}\n' | ocaml-mcp-server --no-dune --no-merlin 2>/dev/null | jq -c 'select(.id == 2) | .result | {is_error: .isError, text: .content[0].text}'
  {"is_error":true,"text":"Merlin not available. Please ensure merlin is installed and configured for your project."}

Test calling non-existent tool:

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nonexistent/tool"}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c 'select(.id == 2) | .error.message'
  "Unknown tool: nonexistent/tool"

Test with invalid arguments for module-signature:

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ocaml/module-signature","arguments":{"wrong_field":"value"}}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c 'select(.id == 2) | .error.message'
  "Failed to parse arguments: Ocaml_mcp_server.module_signature_args"

Test tool input schemas are properly defined:

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c 'select(.id == 2) | .result.tools[] | select(.name == "ocaml/module-signature") | .inputSchema'
  {"type":"object","properties":{"module_path":{"type":"array","items":{"type":"string"}}},"required":["module_path"]}

Test server handles notifications properly (no response expected):

  $ printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ocaml-mcp-server --no-dune 2>/dev/null | jq -c '.id' | grep -v null
  1
  2
