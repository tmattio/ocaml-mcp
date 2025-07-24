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

(** A module for building a high-level, declarative MCP Server. *)
module Server : sig
  type t
  (** An opaque type representing the server configuration. *)

  type pagination_config = { page_size : int }
  (** Configuration for pagination support *)

  type mcp_logging_config = {
    enabled : bool;
    initial_level : LogLevel.t option;
  }
  (** Configuration for MCP protocol logging *)

  val create :
    server_info:ServerInfo.t ->
    ?capabilities:Capabilities.server ->
    ?pagination_config:pagination_config ->
    ?mcp_logging_config:mcp_logging_config ->
    unit ->
    t
  (** [create ~server_info ?capabilities ?mcp_logging_config ()] creates a new
      server builder.
      @param server_info The name and version of your server implementation.
      @param capabilities
        (optional) The capabilities your server supports. Capabilities for
        tools, resources, and prompts are automatically added when you register
        them.
      @param mcp_logging_config
        (optional) Configuration for MCP protocol logging. Defaults to enabled
        with no initial level. *)

  (** A first-class module representing a type that can be converted to and from
      Yojson. Typically derived using `ppx_deriving_yojson`. *)
  module type Json_converter = sig
    type t

    val to_yojson : t -> Yojson.Safe.t
    val of_yojson : Yojson.Safe.t -> (t, string) result
    val schema : unit -> Yojson.Safe.t
  end

  val tool :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?output_schema:Yojson.Safe.t ->
    ?annotations:Mcp.Types.Tool.annotation ->
    ?args:(module Json_converter with type t = 'args) ->
    ('args -> Context.t -> (Mcp.Request.Tools.Call.result, string) result) ->
    unit
  (** [tool t name ?title ?description ?output_schema ?annotations ?args
       handler] registers a tool.

      The handler for the tool is type-safe. You define a record type for the
      tool's arguments, derive `yojson` serializers for it, and pass them as the
      `~args` parameter. The SDK handles JSON schema generation, parsing, and
      validation automatically.

      @param t The server instance.
      @param name The programmatic name of the tool (e.g., "file/write").
      @param title (optional) A human-readable display name for the tool.
      @param description (optional) A brief explanation of what the tool does.
      @param output_schema
        (optional) JSON Schema defining the structure of the tool's output.
      @param annotations (optional) Additional metadata like destructive hints.
      @param args
        (optional) A module implementing [Json_converter] for the argument type.
        If omitted, the tool takes no arguments.
      @param handler
        The function to execute when the tool is called. It receives the parsed,
        type-safe arguments and the request context. *)

  val resource :
    t ->
    string ->
    uri:string ->
    ?description:string ->
    ?mime_type:string ->
    (string -> Context.t -> (Mcp.Request.Resources.Read.result, string) result) ->
    unit
  (** [resource t name ~uri ?description ?mime_type handler] registers a static
      resource with a fixed URI.

      @param handler
        The function to execute when a client reads the resource. It receives
        the URI and context, and must return the resource's contents. *)

  val resource_template :
    t ->
    string ->
    template:string ->
    ?description:string ->
    ?mime_type:string ->
    ?list_handler:
      (Context.t -> (Mcp.Request.Resources.List.result, string) result) ->
    ((string * string) list ->
    Context.t ->
    (Mcp.Request.Resources.Read.result, string) result) ->
    unit
  (** [resource_template t name ~template ?description ?mime_type ?list_handler
       read_handler] registers a resource template for dynamically generated
      resources.

      @param template The URI template (RFC 6570) for the resources.
      @param list_handler
        (optional) A function to enumerate all resources matching this template.
      @param read_handler
        The function to read a specific resource. It receives a list of
        key-value pairs parsed from the URI. *)

  val set_subscription_handler :
    t ->
    on_subscribe:(string -> Context.t -> (unit, string) result) ->
    on_unsubscribe:(string -> Context.t -> (unit, string) result) ->
    unit
  (** [set_subscription_handler t ~on_subscribe ~on_unsubscribe] registers
      handlers for resource subscription requests.

      @param on_subscribe Called when a client subscribes to a resource URI
      @param on_unsubscribe
        Called when a client unsubscribes from a resource URI

      Once set, the server will advertise subscription capability and handle
      subscribe/unsubscribe requests for resources. *)

  val prompt :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?args:(module Json_converter with type t = 'args) ->
    ('args -> Context.t -> (Mcp.Request.Prompts.Get.result, string) result) ->
    unit
  (** [prompt t name ?title ?description ?args handler] registers a prompt.

      Like tools, prompts have type-safe argument handling.

      @param handler
        The function that receives parsed arguments and returns the list of
        messages that constitute the prompt. *)

  val to_mcp_server : t -> Mcp.Server.t
  (** [to_mcp_server t] constructs the final low-level [Mcp.Server.t] instance.
      This is the bridge to the transport layer. The resulting server can be run
      using a connection manager like [Mcp_eio.Connection.serve]. *)

  val setup_mcp_logging : t -> Mcp.Server.t -> unit
  (** [setup_mcp_logging t mcp_server] sets up MCP protocol logging if enabled.
      This should be called after [to_mcp_server] but before serving the
      connection. It will:
      - Set the initial log level if specified in the configuration
      - Install a combined reporter that logs to both console and MCP client
      - Send log messages as MCP notifications *)
end

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
