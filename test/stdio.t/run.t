Test OCaml MCP Server via stdio transport

Initialize the server:
  $ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ocaml-mcp-server --stdio --no-dune 2>/dev/null | tail -1 | jq -c '.result | {name: .serverInfo.name, tools: .capabilities.tools}'
  {"name":"ocaml-mcp-server","tools":{"listChanged":false}}

List available tools:
  $ (
  >   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
  >   echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  > ) | ocaml-mcp-server --stdio --no-dune 2>/dev/null | tail -1 | jq -c '.result.tools[] | {name: .name}'
  {"name":"ocaml_module_signature"}
  {"name":"ocaml_project_structure"}
  {"name":"ocaml_type_at_pos"}
  {"name":"dune_build_status"}
  {"name":"ocaml_find_definition"}
  {"name":"fs_edit"}
  {"name":"dune_run_tests"}
  {"name":"dune_build_target"}
  {"name":"ocaml_find_references"}
  {"name":"fs_write"}
