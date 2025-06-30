# OCaml MCP

OCaml implementation of the Model Context Protocol (MCP), enabling integration between AI assistants and development tools.

## Quick Start

```bash
# Install
opam install  ocaml-mcp-server

# Terminal 1 - Start server
ocaml-mcp-server --socket 8080

# Terminal 2 - Use client
mcp call "dune/build-status" --socket 8080
mcp call "ocaml/module-signature" --socket 8080 \
  -a '{"module_path": ["List"]}'
```

## Libraries

- **mcp** - Core protocol implementation (types, client, server)
- **mcp-eio** - Transport layer (stdio, socket, memory, HTTP)
- **mcp-sdk** - High-level SDK for building MCP servers and clients
- **ocaml-mcp-server** - OCaml development tools server

## Implementation Status

### ✅ Implemented
- Core protocol types and JSON-RPC messaging
- Client/server request-response patterns  
- Notification handling
- Transport layer (stdio, socket, memory, HTTP)
- Server-to-client request handling (sampling, elicitation, roots)
- High-level SDK with type-safe tool/resource/prompt registration
- Dynamic JSON schema generation from OCaml types
- OCaml development tools (Dune build status, module signatures from build artifacts)
- Full compliance with MCP 2025-06-18 specification

### 🚧 In Progress / Missing

**High Priority:**
- **OAuth 2.1 authentication** - Security for production use

**Feature Parity:**
- Request lifecycle:
  - Timeouts
  - **Cancellation** - Currently not supported. The protocol defines `$/cancel` notifications, but implementing proper cancellation requires thread-safe cancellation tokens and checking cancellation status during long operations
  - Progress tracking (basic support implemented)
- Argument completion support
- WebSocket and SSE transports
- Some client helper functions (resources/subscribe, completion/complete, logging/setLevel, ping)

## Examples

See the [examples/](examples/) directory for complete working examples:

- **[weather-server](examples/weather-server/)** - A minimal MCP server that provides weather information

## License

ocaml-mcp is available under the [ISC License](LICENSE).
