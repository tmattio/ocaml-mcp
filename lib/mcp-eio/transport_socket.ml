(** Socket transport implementation *)

open Eio

module Stream_socket = struct
  type t = Socket : 'a Net.stream_socket -> t
end

type t = {
  socket : Stream_socket.t;
  buf_reader : Buf_read.t;
  mutable closed : bool;
}

let create_from_socket socket =
  {
    socket = Stream_socket.Socket socket;
    buf_reader = Buf_read.of_flow ~max_size:1_000_000 (socket :> _ Flow.source);
    closed = false;
  }

let create_server ~net ~sw addr =
  let listening_socket = Net.listen ~sw ~backlog:5 ~reuse_addr:true net addr in
  let socket, _addr = Net.accept ~sw listening_socket in
  create_from_socket socket

let create_client ~net ~sw addr =
  let socket = Net.connect ~sw net addr in
  create_from_socket socket

let send t packet =
  if t.closed then failwith "Transport is closed"
  else
    let (Stream_socket.Socket socket) = t.socket in
    Framing.write_packet (socket :> _ Flow.sink) packet

let recv t = if t.closed then None else Framing.read_packet t.buf_reader

let close t =
  if not t.closed then (
    t.closed <- true;
    let (Stream_socket.Socket socket) = t.socket in
    try Net.close socket with _ -> () (* Ignore errors on close *))
