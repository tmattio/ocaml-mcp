(** Stdio transport implementation *)

open Eio

(* Setup logging *)
let src = Logs.Src.create "mcp.eio.stdio" ~doc:"MCP Eio Stdio Transport logging"

module Log = (val Logs.src_log src : Logs.LOG)

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
    Log.debug (fun m -> m "Sending packet via stdio");
    Framing.write_packet t.stdout packet)

let recv t ~clock ?timeout () =
  if t.closed then (
    Log.debug (fun m -> m "Transport is closed, returning None");
    None)
  else
    match timeout with
    | None ->
        Log.debug (fun m -> m "Reading packet from stdio");
        let result = Framing.read_packet t.buf_reader in
        (match result with
        | None -> Log.debug (fun m -> m "Read returned None (EOF)")
        | Some _ -> Log.debug (fun m -> m "Successfully read packet"));
        result
    | Some duration ->
        Log.debug (fun m ->
            m "Reading packet from stdio with timeout %f" duration);
        Eio.Time.with_timeout_exn clock duration (fun () ->
            Framing.read_packet t.buf_reader)

let close t = t.closed <- true
