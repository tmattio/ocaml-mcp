(** Dune RPC client with registry polling. *)

type diagnostic = {
  file : string;
  line : int;
  column : int;
  message : string;
  severity : [ `Error | `Warning ];
}

type progress =
  | Waiting
  | In_progress of { complete : int; remaining : int; failed : int }
  | Failed
  | Interrupted
  | Success

type t

val create : sw:Eio.Switch.t -> env:Eio_unix.Stdenv.base -> root:string -> t
(** [create ~sw ~env ~root] creates client for project at [root].

    Registry polling discovers Dune instances via XDG_RUNTIME_DIR or
    ~/.cache/dune/rpc. *)

val run : t -> unit
(** [run t] polls registry and processes messages.

    Call in background fiber. Polls every 250ms for Dune instances,
    automatically connects and subscribes to diagnostics and progress. *)

val get_diagnostics : t -> file:string -> diagnostic list
(** [get_diagnostics t ~file] returns diagnostics for [file].

    Empty string returns all diagnostics. *)

val get_progress : t -> progress
(** [get_progress t] returns current build status. *)

val close : t -> unit
(** [close t] disconnects and releases resources. *)
