(** Context for tool execution in OCaml MCP server *)

type t = {
  sw : Eio.Switch.t;
  env : Eio_unix.Stdenv.base;
  project_root : string;
  merlin : Merlin_client.t;
  ocamlformat : Ocamlformat_client.t;
  dune_rpc : Dune_rpc_client.t option;
}
(** Execution context containing Eio resources and OCaml development tool
    clients *)

val create :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  project_root:string ->
  merlin:Merlin_client.t ->
  ocamlformat:Ocamlformat_client.t ->
  dune_rpc:Dune_rpc_client.t option ->
  t
(** [create ~sw ~env ~project_root ~merlin ~ocamlformat ~dune_rpc] constructs a
    new execution context with the provided resources and tool clients. *)
