(** In-memory transport implementation for testing *)

open Eio

type t = {
  send_stream : Jsonrpc.Packet.t Stream.t;
  recv_stream : Jsonrpc.Packet.t Stream.t;
  mutable closed : bool;
}

let create_pair () =
  let stream1 = Stream.create 100 in
  let stream2 = Stream.create 100 in
  let t1 = { send_stream = stream1; recv_stream = stream2; closed = false } in
  let t2 = { send_stream = stream2; recv_stream = stream1; closed = false } in
  (t1, t2)

let send t packet =
  if t.closed then failwith "Transport is closed"
  else Stream.add t.send_stream packet

let recv t ~clock ?timeout () =
  if t.closed then None
  else
    match timeout with
    | None -> Stream.take_nonblocking t.recv_stream
    | Some duration ->
        Eio.Time.with_timeout_exn clock duration (fun () ->
            Some (Stream.take t.recv_stream))

let close t = if not t.closed then t.closed <- true
