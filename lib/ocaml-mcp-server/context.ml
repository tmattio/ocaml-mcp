type t = {
  sw : Eio.Switch.t;
  env : Eio_unix.Stdenv.base;
  project_root : string;
  merlin : Merlin_client.t;
  ocamlformat : Ocamlformat_client.t;
  dune_rpc : Dune_rpc_client.t option;
}

let create ~sw ~env ~project_root ~merlin ~ocamlformat ~dune_rpc =
  { sw; env; project_root; merlin; ocamlformat; dune_rpc }
