Test OCaml MCP Server via stdio transport

Initialize the server:
  $ printf 'Content-Length: 283\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ocaml-mcp-server --stdio --no-dune 2>/dev/null | tail -1 | jq -c '.result | {name: .serverInfo.name, tools: .capabilities.tools}'

List available tools:
  $ (
  >   printf 'Content-Length: 151\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
  >   printf 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  > ) | ocaml-mcp-server --stdio --no-dune 2>/dev/null | tail -1 | jq -c '.result.tools[] | {name: .name}'
  {"name":"fs_write"}
  {"name":"dune_build_status"}
  {"name":"ocaml_find_references"}
  {"name":"dune_run_tests"}
  {"name":"fs_edit"}
  {"name":"ocaml_module_signature"}
  {"name":"ocaml_find_definition"}
  {"name":"dune_build_target"}
  {"name":"ocaml_project_structure"}
  {"name":"ocaml_eval"}
