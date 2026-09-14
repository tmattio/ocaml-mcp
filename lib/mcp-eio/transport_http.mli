(** HTTP transport implementation for MCP.

    This module provides HTTP-based transport for MCP servers and clients.

    For servers, it creates an HTTP server that accepts POST requests with
    JSON-RPC messages in the body and responds with JSON-RPC responses.

    For clients, it sends HTTP POST requests to a specified endpoint. *)

open Eio

type server_config = { port : int; host : string }
(** Server configuration with port and host to bind to. *)

type client_config = { base_url : string; headers : (string * string) list }
(** Client configuration: base URL for the MCP server and extra headers sent
    with every request (e.g. [("Authorization", "Bearer <token>")]). *)

type t
(** Transport instance. *)

val create_server : sw:Switch.t -> port:int -> ?host:string -> unit -> t
(** [create_server ~sw ~port ?host ()] creates HTTP server transport.

    @param sw Switch for structured concurrency
    @param port TCP port to listen on
    @param host Host address to bind to (default: "127.0.0.1") *)

val create_client :
  sw:Switch.t ->
  base_url:string ->
  ?headers:(string * string) list ->
  ?https:
    (Uri.t ->
    [ Eio.Flow.two_way_ty | Eio.Resource.close_ty ] Eio.Std.r ->
    [> Eio.Resource.close_ty ] Eio.Flow.two_way) ->
  < net : _ Eio.Net.t ; .. > ->
  t
(** [create_client ~sw ~base_url ?headers ?https env] creates an HTTP client
    transport speaking the Streamable HTTP protocol: requests advertise
    [Accept: application/json, text/event-stream], [text/event-stream]
    responses are consumed incrementally (each event's data is queued as a
    JSON-RPC message), a server-assigned [Mcp-Session-Id] is echoed on
    subsequent requests, and the protocol version negotiated during
    initialize is sent as [MCP-Protocol-Version].

    To connect to an [https://] server, pass a TLS wrapper as [?https], e.g.
    with [tls-eio]:

    {[
      let () = Mirage_crypto_rng_unix.use_default ()

      let https =
        let authenticator = Result.get_ok (Ca_certs.authenticator ()) in
        let tls_config =
          Result.get_ok (Tls.Config.client ~authenticator ())
        in
        fun uri raw ->
          let host =
            Uri.host uri
            |> Option.map (fun x -> Domain_name.(host_exn (of_string_exn x)))
          in
          Tls_eio.client_of_flow ?host tls_config raw
    ]}

    @param sw Switch for structured concurrency
    @param base_url URL of the MCP endpoint (e.g., "http://localhost:8080")
    @param headers Extra headers sent with every request (default [[]])
    @param https TLS wrapper enabling [https://] URLs (default: HTTP only)
    @param env Eio environment for network access *)

val run_server : t -> < net : _ Eio.Net.t ; .. > -> 'a
(** [run_server t env] runs the HTTP server.

    This function blocks and runs the server until it's closed or an error
    occurs. Must be called on a server transport, not a client transport.

    @param t Server transport instance
    @param env Eio environment for network access *)

include Transport.S with type t := t
(** HTTP transport implements the standard transport interface. *)
