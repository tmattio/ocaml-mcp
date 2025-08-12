Test cancel notifications.

Testing that the "requestId" parameter is correctly parsed as a string or a int:
  $ (
  >   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
  >   echo '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":2,"reason":"This operation was aborted"}}'
  >   echo '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"a-string-id","reason":"This operation was aborted"}}'
  > ) | ocaml-mcp-server --stdio --no-dune
  {"id":1,"jsonrpc":"2.0","result":{"protocolVersion":"2025-06-18","capabilities":{"logging":{"enabled":true},"tools":{"listChanged":false}},"serverInfo":{"name":"ocaml-mcp-server","version":"0.1.0"}}}
