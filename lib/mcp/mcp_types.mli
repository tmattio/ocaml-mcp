module Json_codec : sig
  val decode : 'a Jsont.t -> Jsont.json -> ('a, string) result
  val encode : 'a Jsont.t -> 'a -> Jsont.json
  val integer_json : int Jsont.t
  val number_json : float Jsont.t
  val assoc_json : 'a Jsont.t -> (string * 'a) list Jsont.t
  val find_member : string -> Jsont.json -> Jsont.json option
  val object' : (string * Jsont.json) list -> Jsont.json
  val first_object : 'a Jsont.t -> 'a Jsont.t
  val last_object : 'a Jsont.t -> 'a Jsont.t
end

(** MCP protocol types and data structures.

    This module defines the core types used throughout the Model Context
    Protocol, including request/response structures, capabilities, and content
    types. *)

(** Protocol version constants. *)
module Protocol : sig
  val latest_version : string
  (** [latest_version] is the most recent protocol version. *)

  val default_negotiated_version : string
  (** [default_negotiated_version] is the fallback version used when negotiation
      fails. *)

  val supported_versions : string list
  (** [supported_versions] lists all protocol versions this implementation
      supports. *)

  val jsonrpc_version : string
  (** [jsonrpc_version] is the JSON-RPC version used (always "2.0"). *)
end

(** Request identifier for JSON-RPC. Can be string or integer. *)
type request_id = String of string | Int of int

val request_id_json : request_id Jsont.t

(** Token for tracking long-running operations. Can be string or integer. *)
type progress_token = String of string | Int of int

val progress_token_json : progress_token Jsont.t

type cursor = string

val cursor_json : cursor Jsont.t
(** Opaque pagination cursor. *)

(** JSON-RPC error codes. *)
module ErrorCode : sig
  type t = int

  val json : t Jsont.t
  (** Numeric error code. *)

  val connection_closed : t
  (** [connection_closed] indicates transport was closed. *)

  val request_timeout : t
  (** [request_timeout] indicates request exceeded time limit. *)

  val parse_error : t
  (** [parse_error] indicates invalid JSON. *)

  val invalid_request : t
  (** [invalid_request] indicates malformed JSON-RPC request. *)

  val method_not_found : t
  (** [method_not_found] indicates unknown method name. *)

  val invalid_params : t
  (** [invalid_params] indicates invalid method parameters. *)

  val internal_error : t
  (** [internal_error] indicates server-side error. *)
end

type error = { code : ErrorCode.t; message : string; data : Jsont.json option }

val error_json : error Jsont.t
(** JSON-RPC error response. *)

module OnlyMetaParams : sig
  type t = { meta : Jsont.json option }

  val json : t Jsont.t
  (** Parameters that can be either unit, or only _meta. *)
end

(** Log severity levels. *)
module LogLevel : sig
  (** Severity levels from least to most severe. *)
  type t =
    | Debug
    | Info
    | Notice
    | Warning
    | Error
    | Critical
    | Alert
    | Emergency

  val json : t Jsont.t
end

(** Content types for messages and resources. *)
module Content : sig
  type text = { type_ : string; text : string; meta : Jsont.json option }

  val text_json : text Jsont.t
  (** Text content with MIME type. *)

  type image = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Jsont.json option;
  }

  val image_json : image Jsont.t
  (** Base64-encoded image with MIME type. *)

  type audio = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Jsont.json option;
  }

  val audio_json : audio Jsont.t
  (** Base64-encoded audio with MIME type. *)

  type resource_link = {
    type_ : string;
    uri : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    size : int option;
    annotations : Jsont.json option;
    meta : Jsont.json option;
  }

  val resource_link_json : resource_link Jsont.t
  (** Reference to external resource. *)

  type resource_contents = {
    uri : string;
    mime_type : string option;
    text : string option;
    blob : string option;
    meta : Jsont.json option;
  }

  val resource_contents_json : resource_contents Jsont.t
  (** Resource contents with either text or base64 blob. *)

  type embedded_resource = {
    type_ : string;
    resource : resource_contents;
    meta : Jsont.json option;
  }

  val embedded_resource_json : embedded_resource Jsont.t
  (** Inline resource with contents. *)

  (** Content variants for different media types. *)
  type t =
    | Text of text
    | Image of image
    | Audio of audio
    | ResourceLink of resource_link
    | EmbeddedResource of embedded_resource

  val json : t Jsont.t
end

(** Resource descriptions and templates. *)
module Resource : sig
  type t = {
    uri : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    size : int option;
    annotations : Jsont.json option;
    meta : Jsont.json option;
  }

  val json : t Jsont.t
  (** Resource with URI and metadata. *)

  type template = {
    uri_template : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    annotations : Jsont.json option;
    meta : Jsont.json option;
  }

  val template_json : template Jsont.t
  (** Resource template with URI pattern. *)
end

(** Tool definitions and annotations. *)
module Tool : sig
  type annotation = {
    title : string option;
    read_only : bool option;
    destructive : bool option;
    idempotent : bool option;
    open_world : bool option;
  }

  val annotation_json : annotation Jsont.t
  (** Tool behavior annotations. *)

  type t = {
    name : string;
    title : string option;
    description : string option;
    input_schema : Jsont.json;
    output_schema : Jsont.json option;
    annotations : annotation option;
    meta : Jsont.json option;
  }

  val json : t Jsont.t
  (** Tool with JSON Schema for input/output. *)
end

(** Prompt definitions and messages. *)
module Prompt : sig
  type argument = {
    name : string;
    title : string option;
    description : string option;
    required : bool option;
  }

  val argument_json : argument Jsont.t
  (** Prompt argument specification. *)

  type t = {
    name : string;
    title : string option;
    description : string option;
    arguments : argument list option;
    meta : Jsont.json option;
  }

  val json : t Jsont.t
  (** Prompt template with arguments. *)

  type message = { role : string; content : Content.t }

  val message_json : message Jsont.t
  (** Message with role and content. *)
end

(** Client and server capabilities. *)
module Capabilities : sig
  type roots = { list_changed : bool option }

  val roots_json : roots Jsont.t
  (** Root directory change notifications. *)

  type prompts = { list_changed : bool option }

  val prompts_json : prompts Jsont.t
  (** Prompt list change notifications. *)

  type resources = { subscribe : bool option; list_changed : bool option }

  val resources_json : resources Jsont.t
  (** Resource subscription and change notifications. *)

  type tools = { list_changed : bool option }

  val tools_json : tools Jsont.t
  (** Tool list change notifications. *)

  type client = {
    experimental : Jsont.json option;
    sampling : Jsont.json option;
    elicitation : Jsont.json option;
    roots : roots option;
  }

  val client_json : client Jsont.t
  (** Client-supported capabilities. *)

  type server = {
    experimental : Jsont.json option;
    logging : Jsont.json option;
    completions : Jsont.json option;
    prompts : prompts option;
    resources : resources option;
    tools : tools option;
  }

  val server_json : server Jsont.t
  (** Server-supported capabilities. *)
end

(** Implementation information. *)
module Implementation : sig
  type t = { name : string; version : string }

  val json : t Jsont.t
  (** Implementation name and version. *)
end

(** Client information. *)
module ClientInfo : sig
  type t = { name : string; version : string }

  val json : t Jsont.t
  (** Client name and version. *)
end

(** Server information. *)
module ServerInfo : sig
  type t = { name : string; version : string }

  val json : t Jsont.t
  (** Server name and version. *)
end

(** Root directory information. *)
module Root : sig
  type t = { uri : string; name : string option; meta : Jsont.json option }

  val json : t Jsont.t
  (** Root directory URI with optional name. *)
end

(** Sampling message for model interactions. *)
module SamplingMessage : sig
  type t = { role : string; content : Content.t }

  val json : t Jsont.t
  (** Message with role and content for sampling. *)
end

(** Model hint for sampling. *)
module ModelHint : sig
  type t = { name : string option }

  val json : t Jsont.t
  (** Optional model name hint. *)
end

(** Model selection preferences. *)
module ModelPreferences : sig
  type t = {
    hints : ModelHint.t list option;
    cost_priority : float option;
    speed_priority : float option;
    intelligence_priority : float option;
  }

  val json : t Jsont.t
  (** Preferences for model selection with priority weights. *)
end

(** Completion argument specification. *)
module CompletionArgument : sig
  type t = { name : string; value : string }

  val json : t Jsont.t
  (** Named argument with value. *)
end

(** Completion reference types. *)
module CompletionReference : sig
  (** Reference to completable items by type and name. *)
  type t = Resource of string | ResourceTemplate of string | Prompt of string

  val json : t Jsont.t
end

(** Completion result with pagination. *)
module Completion : sig
  type t = { values : string list; total : int option; has_more : bool option }

  val json : t Jsont.t
  (** Completion values with optional pagination info. *)
end

(** Primitive schema definitions for elicitation. *)
module PrimitiveSchema : sig
  type string_schema = {
    type_ : string;
    title : string option;
    description : string option;
    format : string option;
    min_length : int option;
    max_length : int option;
  }

  val string_schema_json : string_schema Jsont.t

  type number_schema = {
    type_ : string;
    title : string option;
    description : string option;
    minimum : int option;
    maximum : int option;
  }

  val number_schema_json : number_schema Jsont.t

  type boolean_schema = {
    type_ : string;
    title : string option;
    description : string option;
    default : bool option;
  }

  val boolean_schema_json : boolean_schema Jsont.t

  type enum_schema = {
    type_ : string;
    title : string option;
    description : string option;
    enum : string list;
    enum_names : string list option;
  }

  val enum_schema_json : enum_schema Jsont.t

  type t =
    | String of string_schema
    | Number of number_schema
    | Boolean of boolean_schema
    | Enum of enum_schema

  val json : t Jsont.t
end

(** Elicitation schema for structured input. *)
module ElicitationSchema : sig
  type t = {
    type_ : string;
    properties : (string * PrimitiveSchema.t) list;
    required : string list;
  }

  val json : t Jsont.t
end
