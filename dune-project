(lang dune 3.19)

(name mcp)

(generate_opam_files true)

(source
 (github tmattio/ocaml-mcp))

(authors "Thibaut Mattio <thibaut.mattio@gmail.com>")

(maintainers "Thibaut Mattio <thibaut.mattio@gmail.com>")

(license ISC)

(implicit_transitive_deps false)

(package
 (name mcp)
 (synopsis "Model Context Protocol implementation for OCaml")
 (description
  "An OCaml implementation of the Model Context Protocol (MCP), providing both client and server libraries")
 (depends
  ocaml
  logs
  jsonrpc
  jsonschema
  yojson
  (jsont (>= 0.4.0))
  bytesrw
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
  (jsont (>= 0.4.0))
  http
  cohttp-eio
  (alcotest :with-test)
  (eio_main :with-test)))

(package
 (name ocaml-mcp-server)
 (synopsis "MCP server providing tools for OCaml development")
 (description
  "An MCP (Model Context Protocol) server that provides tools for OCaml development, including integration with dune build system.")
 (depends ocaml mcp mcp-eio eio_main jsont ocaml-platform-sdk cmdliner (alcotest :with-test)))
