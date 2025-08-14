# OCaml MCP

Supercharge OCaml development with AI coding agents. This [MCP](https://modelcontextprotocol.io/) server gives AI assistants deep integration with your OCaml projects through Dune, Merlin, and other OCaml Platform tools.

## What is MCP?

MCP is an open protocol that enables AI models to securely access local services and tools. This project provides both the core protocol implementation for OCaml and a ready-to-use development server.

## Project Overview

This repository contains:

- **Protocol Libraries** - Build your own MCP servers and clients in OCaml
  - **mcp** - Core protocol implementation (types, client, server)
  - **mcp-eio** - Transport layer (stdio, socket, memory, HTTP)
  - **mcp-sdk** - High-level SDK for building MCP servers and clients

- **OCaml Development Server**
  - **ocaml-mcp-server** - Ready-to-use MCP server with OCaml development tools


## Building

```bash
make init
make build
```

## Installation

```bash
make install
```

## Usage

```bash
# Using stdio
ocaml-mcp-server

# As an HTTP server
ocaml-mcp-server --socket 8080
```

## Features

The `ocaml-mcp-server` provides comprehensive OCaml development tools:

**Dune Build System Integration**
- `dune/build-status` - Real-time build status with error reporting
- `dune/build-target` - Build specific targets with streaming output
- `dune/run-tests` - Execute tests with detailed results (🚧 WIP - no tests)

**OCaml Code Analysis**
- `ocaml/module-signature` - Get module signatures from compiled artifacts
- `ocaml/find-definition` - Jump to symbol definitions (🚧 WIP - no tests)
- `ocaml/find-references` - Find all usages of a symbol (🚧 WIP - no tests)
- `ocaml/type-at-pos` - Get type information at cursor position (🚧 WIP - no tests)
- `ocaml/project-structure` - Analyze project layout and dependencies
- `ocaml/eval` - Evaluate OCaml expressions in project context

**File System Tools (with OCaml superpowers)**
- `fs/read` - Read files with automatic Merlin diagnostics for OCaml code
- `fs/write` - Write files with automatic OCaml formatting
- `fs/edit` - Edit files while preserving OCaml syntax validity

The server integrates with Merlin, Dune RPC, ocamlformat, and other OCaml Platform tools.

## MCP Protocol Implementation Status

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

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

`ocaml-mcp` is available under the [ISC License](LICENSE).
