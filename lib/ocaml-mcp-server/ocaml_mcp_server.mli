(** OCaml MCP Server.

    This server provides OCaml development tools through the Model Context
    Protocol, integrating with Dune build system and Merlin for code
    intelligence.

    {1 Configuration} *)

type config = {
  project_root : string option;
      (** Project root directory. Auto-detected if None. *)
  enable_dune : bool;  (** Enable Dune RPC for build status and diagnostics. *)
  enable_merlin : bool;  (** Enable Merlin for code intelligence. *)
}

val default_config : config
(** [default_config] enables all features with auto-detected project root. *)

(** {1 Server Creation} *)

val create_server :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  config:config ->
  Mcp_sdk.Server.t
(** [create_server ~sw ~env ~config] creates MCP server using the SDK.

    Initializes Dune RPC polling and Merlin integration based on config. *)

val run_stdio : env:Eio_unix.Stdenv.base -> config:config -> unit
(** [run_stdio ~env ~config] runs server on stdin/stdout. *)

val run :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  connection:Mcp_eio.Connection.t ->
  config:config ->
  unit
(** [run ~sw ~env ~connection ~config] runs server on provided connection. *)
