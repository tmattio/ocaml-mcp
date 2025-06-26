(** HTTP transport implementation for MCP.

    This module provides HTTP-based transport for MCP servers and clients.

    For servers, it creates an HTTP server that accepts POST requests with
    JSON-RPC messages in the body and responds with JSON-RPC responses.

    For clients, it sends HTTP POST requests to a specified endpoint. *)

open Eio

type server_config = { port : int; host : string }
(** Server configuration with port and host to bind to. *)

type client_config = { base_url : string }
(** Client configuration with base URL for the MCP server. *)

type t
(** Transport instance. *)

val create_server : sw:Switch.t -> port:int -> ?host:string -> unit -> t
(** [create_server ~sw ~port ?host ()] creates HTTP server transport.

    @param sw Switch for structured concurrency
    @param port TCP port to listen on
    @param host Host address to bind to (default: "127.0.0.1") *)

val create_client :
  sw:Switch.t -> base_url:string -> < net : _ Eio.Net.t ; .. > -> t
(** [create_client ~sw ~base_url env] creates HTTP client transport.

    @param sw Switch for structured concurrency
    @param base_url Base URL of the MCP server (e.g., "http://localhost:8080")
    @param env Eio environment for network access *)

val run_server : t -> < net : _ Eio.Net.t ; .. > -> 'a
(** [run_server t env] runs the HTTP server.

    This function blocks and runs the server until it's closed or an error
    occurs. Must be called on a server transport, not a client transport.

    @param t Server transport instance
    @param env Eio environment for network access *)

include Transport.S with type t := t
(** HTTP transport implements the standard transport interface. *)
