(** MCP SDK with Eio async support.

    This module provides async versions of the MCP SDK handlers, allowing
    handlers to return Eio promises for non-blocking operations.

    Example usage:
    {[
      open Mcp_sdk_eio

      let async_tool_handler args ctx =
        (* Perform async operations *)
        Eio.Fiber.yield ();
        async_ok Tool_result.(text "Done!")

      let server =
        Server.create ~server_info () Server.tool server "my-async-tool"
          async_tool_handler
    ]} *)

(** {1 Async Context} *)

module Context : sig
  include module type of Mcp_sdk.Context

  val report_progress_async :
    t -> sw:Eio.Switch.t -> progress:float -> ?total:float -> unit -> unit
  (** Report progress asynchronously in a separate fiber *)
end

(** {1 Async Server} *)

module Server : sig
  type t
  (** Async server instance *)

  val create :
    server_info:Mcp.Types.ServerInfo.t ->
    ?capabilities:Mcp.Types.Capabilities.server ->
    ?pagination_config:Mcp_sdk.Server.pagination_config ->
    ?mcp_logging_config:Mcp_sdk.Server.mcp_logging_config ->
    unit ->
    t
  (** Create a new async server *)

  (** {2 Tool Registration} *)

  val tool :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?output_schema:Yojson.Safe.t ->
    ?annotations:Mcp.Types.Tool.annotation ->
    ?args:(module Mcp_sdk.Server.Json_converter with type t = 'a) ->
    ('a ->
    Context.t ->
    (Mcp.Request.Tools.Call.result, string) result Eio.Promise.t) ->
    unit
  (** Register an async tool handler.

      The handler returns an Eio promise, allowing for non-blocking operations
      like network calls or file I/O. *)

  (** {2 Resource Registration} *)

  val resource :
    t ->
    string ->
    uri:string ->
    ?description:string ->
    ?mime_type:string ->
    (string ->
    Context.t ->
    (Mcp.Request.Resources.Read.result, string) result Eio.Promise.t) ->
    unit
  (** Register an async static resource handler *)

  val resource_template :
    t ->
    string ->
    template:string ->
    ?description:string ->
    ?mime_type:string ->
    ?list_handler:
      (Context.t ->
      (Mcp.Request.Resources.List.result, string) result Eio.Promise.t) ->
    ((string * string) list ->
    Context.t ->
    (Mcp.Request.Resources.Read.result, string) result Eio.Promise.t) ->
    unit
  (** Register an async resource template handler *)

  (** {2 Prompt Registration} *)

  val prompt :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?args:(module Mcp_sdk.Server.Json_converter with type t = 'a) ->
    ('a ->
    Context.t ->
    (Mcp.Request.Prompts.Get.result, string) result Eio.Promise.t) ->
    unit
  (** Register an async prompt handler *)

  (** {2 Subscription Handlers} *)

  val set_subscription_handler :
    t ->
    on_subscribe:(string -> Context.t -> (unit, string) result Eio.Promise.t) ->
    on_unsubscribe:(string -> Context.t -> (unit, string) result Eio.Promise.t) ->
    unit
  (** Set async subscription handlers *)

  (** {2 Server Operations} *)

  val to_mcp_server : sw:Eio.Switch.t -> t -> Mcp.Server.t
  (** Convert async server to MCP server.

      This creates a synchronous MCP server that internally awaits the async
      handlers' promises. *)

  val run :
    sw:Eio.Switch.t ->
    env:Eio_unix.Stdenv.base ->
    t ->
    Mcp_eio.Connection.t ->
    unit
  (** Run the async server on a connection *)
end

(** {1 Helper Functions} *)

val async : 'a -> 'a Eio.Promise.t
(** Create a resolved promise with the given value *)

val async_ok : 'a -> ('a, 'b) result Eio.Promise.t
(** Create a resolved promise with Ok value *)

val async_error : string -> ('a, string) result Eio.Promise.t
(** Create a resolved promise with Error value *)
