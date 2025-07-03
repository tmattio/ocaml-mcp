# todo

- test diagnostic on fs-tools (e.g. warning, error)
- improve logging
- bug: initializating MCP multiple times (Starting OCaml MCP Server / )
- idea: project is a tree of modules, not files, agent works on modules
- timeout on commands (build especially)
- bubblewrap to sandbox tools (eval, build, fs/*)
- support cancellation
- format tool
- forbid edit/write if not read

- need to process opam-repository, compile a cached file (with key=commit)
  - easy search. needed to get versions of packages for reading module signature.
  - next: see which repo the project is using (either opam, or with dune-workspace)
  - next: later on, can think of more powerful search of source code, generate embedding for semantic search

- read module signature:
  - if part of project, use merlin.
  - if installed library, check if we use dune pkg, is it in _build/private/.pkg/
  - if installed library, if using opam, check in the installed files (maybe use findlib?)
  - if not, make request to (https://docs-data.ocaml.org/live/p/<package>/<version>/) (we can check the versions at )
