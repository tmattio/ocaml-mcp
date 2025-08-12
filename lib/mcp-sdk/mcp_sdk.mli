(** High-Level SDK for the Model Context Protocol in OCaml. *)

open Mcp.Types
open Mcp.Protocol

(** MCP Logging support *)
module Logging : sig
  val map_mcp_to_logs_level : LogLevel.t -> Logs.level option
  (** [map_mcp_to_logs_level level] converts an MCP LogLevel to an OCaml Logs
      level *)

  val add_mcp_notifier :
    send_notification:(Mcp.Notification.t -> unit) ->
    Logs.reporter ->
    Logs.reporter
  (** [add_mcp_notifier ~send_notification reporter] combines the given reporter
      with an MCP notifier that sends log messages as MCP notifications. The
      existing reporter continues to work normally. *)
end

(** The context passed to every server-side request handler. It provides access
    to request-specific information and actions. *)
module Context : sig
  type t
  (** An opaque type representing the request context. *)

  val request_id : t -> request_id
  (** [request_id t] returns the unique identifier of the incoming request.
      Useful for logging, tracking, or correlating operations. *)

  val progress_token : t -> progress_token option
  (** [progress_token t] returns the progress token if the client requested
      progress updates for this operation. Returns [None] otherwise. *)

  val send_notification : t -> Mcp.Notification.t -> unit
  (** [send_notification t notification] sends a notification to the client in
      the context of the current request. This is the preferred way to send
      progress updates or other related notifications. *)

  val report_progress : t -> progress:float -> ?total:float -> unit -> unit
  (** [report_progress t ~progress ?total ()] sends a progress notification to
      the client if a progress token was provided with the request. The
      [progress] parameter indicates the current progress value, and [total]
      optionally indicates the total amount of work. If no progress token is
      available, this function does nothing. *)

  val meta : t -> Yojson.Safe.t option
  (** [meta t] returns the metadata object from the request, if provided. *)
end

(** Helper functions for creating tool results *)
module Tool_result : sig
  val create :
    ?content:Mcp.Types.Content.t list ->
    ?structured_content:Yojson.Safe.t ->
    ?is_error:bool ->
    unit ->
    Mcp.Request.Tools.Call.result
  (** [create ?content ?structured_content ?is_error ()] creates a tool result.

      @param content Text or resource content to return
      @param structured_content
        JSON data that conforms to the tool's output schema
      @param is_error Whether this result represents an error *)

  val text : string -> Mcp.Request.Tools.Call.result
  (** [text s] creates a simple text result *)

  val error : string -> Mcp.Request.Tools.Call.result
  (** [error msg] creates an error result with the given message *)

  val structured :
    ?text:string -> Yojson.Safe.t -> Mcp.Request.Tools.Call.result
  (** [structured ?text json] creates a result with structured content.
      Optionally includes a text description. *)
end

module type Json_converter = sig
  type t

  val to_yojson : t -> Yojson.Safe.t
  val of_yojson : Yojson.Safe.t -> (t, string) result
  val schema : unit -> Yojson.Safe.t
end

module type Io = sig
  type 'a t

  val return : 'a -> 'a t
  val map : ('a -> 'b) -> 'a t -> 'b t
  val run : 'a t -> 'a
end

module Make_server (Io : Io) : sig
  type t
  type pagination_config = { page_size : int }

  type mcp_logging_config = {
    enabled : bool;
    initial_level : Mcp.Types.LogLevel.t option;
  }

  val create :
    server_info:Mcp.Types.ServerInfo.t ->
    ?capabilities:Mcp.Types.Capabilities.server ->
    ?pagination_config:pagination_config ->
    ?mcp_logging_config:mcp_logging_config ->
    unit ->
    t

  val tool :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?output_schema:Yojson.Safe.t ->
    ?annotations:Mcp.Types.Tool.annotation ->
    ?args:(module Json_converter with type t = 'args) ->
    ('args -> Context.t -> (Mcp.Request.Tools.Call.result, string) result Io.t) ->
    unit

  val resource :
    t ->
    string ->
    uri:string ->
    ?description:string ->
    ?mime_type:string ->
    (string ->
    Context.t ->
    (Mcp.Request.Resources.Read.result, string) result Io.t) ->
    unit

  val resource_template :
    t ->
    string ->
    template:string ->
    ?description:string ->
    ?mime_type:string ->
    ?list_handler:
      (Context.t -> (Mcp.Request.Resources.List.result, string) result Io.t) ->
    ((string * string) list ->
    Context.t ->
    (Mcp.Request.Resources.Read.result, string) result Io.t) ->
    unit

  val set_subscription_handler :
    t ->
    on_subscribe:(string -> Context.t -> (unit, string) result Io.t) ->
    on_unsubscribe:(string -> Context.t -> (unit, string) result Io.t) ->
    unit

  val prompt :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?args:(module Json_converter with type t = 'args) ->
    ('args -> Context.t -> (Mcp.Request.Prompts.Get.result, string) result Io.t) ->
    unit

  val to_mcp_server : t -> Mcp.Server.t
  val setup_mcp_logging : t -> Mcp.Server.t -> unit
end

module Server : Server.S
(** A high-level MCP server implementation that provides a declarative API for
    registering tools, resources, and handling requests. *)

(** High-level MCP Client with helpers for creating requests. *)
module Client : sig
  type t
  (** An opaque type representing the client configuration. *)

  val create :
    client_info:ClientInfo.t -> client_capabilities:Capabilities.client -> t
  (** [create ~client_info ~client_capabilities] creates a new client builder.
  *)

  val get_mcp_client : t -> Mcp.Client.t
  (** [get_mcp_client t] returns the underlying low-level [Mcp.Client.t]. This
      is needed to run the client on a connection via a library like
      [Mcp_eio.Connection.run_client]. *)

  val initialize :
    t ->
    ((Mcp.Request.Initialize.result, string) result -> unit) ->
    outgoing_message
  (** [initialize t callback] prepares an initialization message. The caller is
      responsible for sending the returned [outgoing_message]. The [callback]
      will be invoked with the parsed result from the server. This function is
      I/O-agnostic. The application layer (e.g., using Eio) is responsible for
      managing the asynchronous nature of the call. *)

  val tools_list :
    t ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Tools.List.result, string) result -> unit) ->
    outgoing_message
  (** [tools_list t callback] prepares a request to list available tools. *)

  val tools_call :
    t ->
    name:string ->
    args:'args ->
    args_to_yojson:('args -> Yojson.Safe.t) ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Tools.Call.result, string) result -> unit) ->
    outgoing_message
  (** [tools_call t ~name ~args ~args_to_yojson callback] prepares a request to
      call a remote tool. The [args] record is automatically converted to JSON
      using the provided `args_to_yojson` function. *)

  val resources_list :
    t ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Resources.List.result, string) result -> unit) ->
    outgoing_message
  (** [resources_list t callback] prepares a request to list resources. *)

  val resources_read :
    t ->
    uri:string ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Resources.Read.result, string) result -> unit) ->
    outgoing_message
  (** [resources_read t ~uri callback] prepares a request to read a resource. *)

  val prompts_list :
    t ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Prompts.List.result, string) result -> unit) ->
    outgoing_message
  (** [prompts_list t callback] prepares a request to list prompts. *)

  val prompts_get :
    t ->
    name:string ->
    args:'args ->
    args_to_yojson:('args -> Yojson.Safe.t) ->
    ?meta:Yojson.Safe.t ->
    ((Mcp.Request.Prompts.Get.result, string) result -> unit) ->
    outgoing_message
  (** [prompts_get t ~name ~args ~args_to_yojson callback] prepares a request to
      retrieve a prompt, substituting the given arguments. *)
end
