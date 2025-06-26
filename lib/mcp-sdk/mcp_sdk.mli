(** High-Level SDK for the Model Context Protocol in OCaml. *)

open Mcp.Types
open Mcp.Protocol

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
end

(** A module for building a high-level, declarative MCP Server. *)
module Server : sig
  type t
  (** An opaque type representing the server configuration. *)

  val create :
    server_info:ServerInfo.t -> ?capabilities:Capabilities.server -> unit -> t
  (** [create ~server_info ?capabilities ()] creates a new server builder.
      @param server_info The name and version of your server implementation.
      @param capabilities
        (optional) The capabilities your server supports. Capabilities for
        tools, resources, and prompts are automatically added when you register
        them. *)

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
    ?args:(module Json_converter with type t = 'args) ->
    ('args -> Context.t -> (Mcp.Request.Tools.Call.result, string) result) ->
    unit
  (** [tool t name ?title ?description ?args handler] registers a tool.

      The handler for the tool is type-safe. You define a record type for the
      tool's arguments, derive `yojson` serializers for it, and pass them as the
      `~args` parameter. The SDK handles JSON schema generation, parsing, and
      validation automatically.

      @param t The server instance.
      @param name The programmatic name of the tool (e.g., "file/write").
      @param title (optional) A human-readable display name for the tool.
      @param description (optional) A brief explanation of what the tool does.
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
    ((Mcp.Request.Tools.List.result, string) result -> unit) ->
    outgoing_message
  (** [tools_list t callback] prepares a request to list available tools. *)

  val tools_call :
    t ->
    name:string ->
    args:'args ->
    args_to_yojson:('args -> Yojson.Safe.t) ->
    ((Mcp.Request.Tools.Call.result, string) result -> unit) ->
    outgoing_message
  (** [tools_call t ~name ~args ~args_to_yojson callback] prepares a request to
      call a remote tool. The [args] record is automatically converted to JSON
      using the provided `args_to_yojson` function. *)

  val resources_list :
    t ->
    ((Mcp.Request.Resources.List.result, string) result -> unit) ->
    outgoing_message
  (** [resources_list t callback] prepares a request to list resources. *)

  val resources_read :
    t ->
    uri:string ->
    ((Mcp.Request.Resources.Read.result, string) result -> unit) ->
    outgoing_message
  (** [resources_read t ~uri callback] prepares a request to read a resource. *)

  val prompts_list :
    t ->
    ((Mcp.Request.Prompts.List.result, string) result -> unit) ->
    outgoing_message
  (** [prompts_list t callback] prepares a request to list prompts. *)

  val prompts_get :
    t ->
    name:string ->
    args:'args ->
    args_to_yojson:('args -> Yojson.Safe.t) ->
    ((Mcp.Request.Prompts.Get.result, string) result -> unit) ->
    outgoing_message
  (** [prompts_get t ~name ~args ~args_to_yojson callback] prepares a request to
      retrieve a prompt, substituting the given arguments. *)
end
