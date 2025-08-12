module Context = Common.Context

(** A module for building a high-level, declarative MCP Server. *)
module type S = sig
  type t
  (** An opaque type representing the server configuration. *)

  type pagination_config = { page_size : int }
  (** Configuration for pagination support *)

  type mcp_logging_config = {
    enabled : bool;
    initial_level : Mcp.Types.LogLevel.t option;
  }
  (** Configuration for MCP protocol logging *)

  val create :
    server_info:Mcp.Types.ServerInfo.t ->
    ?capabilities:Mcp.Types.Capabilities.server ->
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

  val tool :
    t ->
    string ->
    ?title:string ->
    ?description:string ->
    ?output_schema:Yojson.Safe.t ->
    ?annotations:Mcp.Types.Tool.annotation ->
    ?args:(module Common.Json_converter with type t = 'args) ->
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
    ?args:(module Common.Json_converter with type t = 'args) ->
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
