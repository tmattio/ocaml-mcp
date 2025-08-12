(** Connection management for MCP over various transports *)

(* Setup logging *)
let src = Logs.Src.create "mcp.eio.connection" ~doc:"MCP Eio Connection logging"

module Log = (val Logs.src_log src : Logs.LOG)

type transport = {
  send : Jsonrpc.Packet.t -> unit;
  recv : ?timeout:float -> unit -> Jsonrpc.Packet.t option;
  close : unit -> unit;
}

type t = { transport : transport }

let create ~clock (type a) (module T : Transport.S with type t = a)
    (transport : a) =
  {
    transport =
      {
        send = T.send transport;
        recv = (fun ?timeout () -> T.recv transport ~clock ?timeout ());
        close = (fun () -> T.close transport);
      };
  }

let send t outgoing_msg =
  let packet = Mcp.Protocol.outgoing_to_message outgoing_msg in
  t.transport.send packet

let recv t ?timeout () =
  match t.transport.recv ?timeout () with
  | None -> None
  | Some packet -> (
      match Mcp.Protocol.parse_message packet with
      | Ok msg -> Some msg
      | Error err ->
          (* Log error and skip malformed message *)
          Log.err (fun m -> m "Failed to parse message: %s" err);
          None)

let close t = t.transport.close ()

let serve ~sw:_ t server =
  let rec loop () =
    match recv t () with
    | None ->
        Log.info (fun m -> m "Client disconnected");
        () (* EOF, exit loop *)
    | Some msg ->
        (match msg with
        | Mcp.Protocol.Request (id, req) ->
            Log.info (fun m ->
                m "Received request: %s (id: %s)"
                  (Mcp.Request.method_name req)
                  (match id with `String s -> s | `Int i -> string_of_int i))
        | Mcp.Protocol.Notification notif ->
            Log.info (fun m ->
                m "Received notification: %s"
                  (Mcp.Notification.method_name notif))
        | Mcp.Protocol.Response (_, _) ->
            Log.debug (fun m -> m "Received response (unexpected in server)")
        | _ -> Log.debug (fun m -> m "Received batch message"));
        (match Mcp.Server.handle_message server msg with
        | Some response ->
            Log.debug (fun m -> m "Sending response");
            send t response
        | None -> Log.debug (fun m -> m "No response needed"));
        loop ()
  in
  try
    loop ();
    Log.debug (fun m -> m "Server loop ended")
  with exn ->
    Log.err (fun m -> m "Server error: %s" (Printexc.to_string exn));
    close t

let run_client ~sw:_ t client =
  let rec loop () =
    match recv t () with
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
