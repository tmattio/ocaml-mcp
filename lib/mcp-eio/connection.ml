(** Connection management for MCP over various transports *)

module Log = Logging

type transport = {
  send : Jsonrpc.Packet.t -> unit;
  recv : unit -> Jsonrpc.Packet.t option;
  close : unit -> unit;
}

type t = { transport : transport }

let create (type a) (module T : Transport.S with type t = a) (transport : a) =
  {
    transport =
      {
        send = T.send transport;
        recv = (fun () -> T.recv transport);
        close = (fun () -> T.close transport);
      };
  }

let send t outgoing_msg =
  let packet = Mcp.Protocol.outgoing_to_message outgoing_msg in
  t.transport.send packet

let recv t =
  match t.transport.recv () with
  | None ->
      Log.debug "Transport returned None (EOF)";
      None
  | Some packet -> (
      Log.debug "Raw packet received";
      match Mcp.Protocol.parse_message packet with
      | Ok msg -> Some msg
      | Error err ->
          (* Log error and skip malformed message *)
          Log.error "Failed to parse message: %s" err;
          None)

let close t = t.transport.close ()

let serve ~sw:_ t server =
  Log.info "Starting MCP server";
  let rec loop () =
    Log.debug "Waiting for message...";
    match recv t with
    | None ->
        Log.debug "End of file received, exiting server loop";
        () (* EOF, exit loop *)
    | Some msg ->
        Log.debug "Processing message";
        (match Mcp.Server.handle_message server msg with
        | Some response ->
            Log.debug "Sending response";
            send t response
        | None -> Log.debug "No response needed");
        loop ()
  in
  try
    loop ();
    Log.info "Server loop ended normally"
  with exn ->
    Log.error "Server error: %s" (Printexc.to_string exn);
    close t

let run_client ~sw:_ t client =
  let rec loop () =
    match recv t with
    | None -> () (* EOF, exit loop *)
    | Some msg ->
        (match Mcp.Client.handle_message client msg with
        | Some response -> send t response
        | None -> ());
        loop ()
  in
  try loop ()
  with exn ->
    Eio.traceln "Client error: %s" (Printexc.to_string exn);
    close t

(* Helper function to send a request from client and get the outgoing message *)
let send_request t client request callback =
  let outgoing = Mcp.Client.send_request client request callback in
  send t outgoing

(* Helper function to send a notification *)
let send_notification t notification =
  let outgoing =
    match notification with
    | `Server (server, notif) -> Mcp.Server.send_notification server notif
    | `Client (client, notif) -> Mcp.Client.send_notification client notif
  in
  send t outgoing
