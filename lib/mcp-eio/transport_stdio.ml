(** Stdio transport implementation *)

open Eio
module Log = Logging

type stdin = Flow.source_ty Eio.Std.r
type stdout = Flow.sink_ty Eio.Std.r

type t = {
  _stdin : stdin; (* Kept for potential future use *)
  stdout : stdout;
  buf_reader : Buf_read.t;
  mutable closed : bool;
}

let create ~stdin ~stdout =
  {
    _stdin = (stdin :> stdin);
    stdout :> stdout;
    buf_reader = Buf_read.of_flow ~max_size:1_000_000 stdin;
    closed = false;
  }

let send t packet =
  if t.closed then failwith "Transport is closed"
  else (
    Log.debug "Sending packet via stdio";
    Framing.write_packet t.stdout packet)

let recv t =
  if t.closed then (
    Log.debug "Transport is closed, returning None";
    None)
  else (
    Log.debug "Reading packet from stdio";
    let result = Framing.read_packet t.buf_reader in
    (match result with
    | None -> Log.debug "Read returned None (EOF)"
    | Some _ -> Log.debug "Successfully read packet");
    result)

let close t = t.closed <- true
