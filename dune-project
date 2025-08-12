(lang dune 3.19)

(name mcp)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name <author@example.com>")

(maintainers "Maintainer Name <maintainer@example.com>")

(license LICENSE)

(implicit_transitive_deps false)

(package
 (name mcp)
 (synopsis "Model Context Protocol implementation for OCaml")
 (description
  "An OCaml implementation of the Model Context Protocol (MCP), providing both client and server libraries")
 (depends
  ocaml
  jsonrpc
  jsonschema
  yojson
  ppx_inline_test
  ppx_deriving_yojson
  logs
  re
  (alcotest :with-test))
 (tags
  (mcp protocol rpc)))

(package
 (name mcp-eio)
 (synopsis "Eio-based transport layer for MCP")
 (description
  "Provides stdio, socket, and in-memory transports for the Model Context Protocol")
 (depends
  ocaml
  eio
  mcp
  http
  cohttp-eio
  (eio_main :with-test)))

(package
 (name ocaml-mcp-server)
 (synopsis "MCP server providing tools for OCaml development")
 (description
  "An MCP (Model Context Protocol) server that provides tools for OCaml development, including integration with dune build system.")
 (depends ocaml mcp mcp-eio eio_main ocaml-platform-sdk cmdliner))
