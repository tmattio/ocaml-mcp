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
type request_id = String of string | Int of int [@@deriving yojson]

(** Token for tracking long-running operations. Can be string or integer. *)
type progress_token = String of string | Int of int [@@deriving yojson]

type cursor = string [@@deriving yojson]
(** Opaque pagination cursor. *)

(** JSON-RPC error codes. *)
module ErrorCode : sig
  type t = int [@@deriving yojson]
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

type error = {
  code : ErrorCode.t;
  message : string;
  data : Yojson.Safe.t option;
}
[@@deriving yojson { strict = false }]
(** JSON-RPC error response. *)

module OnlyMetaParams : sig
  type t = { meta : Yojson.Safe.t option [@default None] [@key "_meta"] }
  [@@deriving yojson { strict = false }]
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
  [@@deriving yojson]
end

(** Content types for messages and resources. *)
module Content : sig
  type text = {
    type_ : string;
    text : string;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Text content with MIME type. *)

  type image = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Base64-encoded image with MIME type. *)

  type audio = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Base64-encoded audio with MIME type. *)

  type resource_link = {
    type_ : string;
    uri : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    size : int option;
    annotations : Yojson.Safe.t option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Reference to external resource. *)

  type resource_contents = {
    uri : string;
    mime_type : string option;
    text : string option;
    blob : string option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Resource contents with either text or base64 blob. *)

  type embedded_resource = {
    type_ : string;
    resource : resource_contents;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Inline resource with contents. *)

  (** Content variants for different media types. *)
  type t =
    | Text of text
    | Image of image
    | Audio of audio
    | ResourceLink of resource_link
    | EmbeddedResource of embedded_resource
  [@@deriving yojson { strict = false }]
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
    annotations : Yojson.Safe.t option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Resource with URI and metadata. *)

  type template = {
    uri_template : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    annotations : Yojson.Safe.t option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
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
  [@@deriving yojson { strict = false }]
  (** Tool behavior annotations. *)

  type t = {
    name : string;
    title : string option;
    description : string option;
    input_schema : Yojson.Safe.t;
    output_schema : Yojson.Safe.t option;
    annotations : annotation option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
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
  [@@deriving yojson { strict = false }]
  (** Prompt argument specification. *)

  type t = {
    name : string;
    title : string option;
    description : string option;
    arguments : argument list option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Prompt template with arguments. *)

  type message = { role : string; content : Content.t }
  [@@deriving yojson { strict = false }]
  (** Message with role and content. *)
end

(** Client and server capabilities. *)
module Capabilities : sig
  type roots = { list_changed : bool option }
  [@@deriving yojson { strict = false }]
  (** Root directory change notifications. *)

  type prompts = { list_changed : bool option }
  [@@deriving yojson { strict = false }]
  (** Prompt list change notifications. *)

  type resources = { subscribe : bool option; list_changed : bool option }
  [@@deriving yojson { strict = false }]
  (** Resource subscription and change notifications. *)

  type tools = { list_changed : bool option }
  [@@deriving yojson { strict = false }]
  (** Tool list change notifications. *)

  type client = {
    experimental : Yojson.Safe.t option;
    sampling : Yojson.Safe.t option;
    elicitation : Yojson.Safe.t option;
    roots : roots option;
  }
  [@@deriving yojson { strict = false }]
  (** Client-supported capabilities. *)

  type server = {
    experimental : Yojson.Safe.t option;
    logging : Yojson.Safe.t option;
    completions : Yojson.Safe.t option;
    prompts : prompts option;
    resources : resources option;
    tools : tools option;
  }
  [@@deriving yojson { strict = false }]
  (** Server-supported capabilities. *)
end

(** Implementation information. *)
module Implementation : sig
  type t = { name : string; version : string }
  [@@deriving yojson { strict = false }]
  (** Implementation name and version. *)
end

(** Client information. *)
module ClientInfo : sig
  type t = { name : string; version : string }
  [@@deriving yojson { strict = false }]
  (** Client name and version. *)
end

(** Server information. *)
module ServerInfo : sig
  type t = { name : string; version : string }
  [@@deriving yojson { strict = false }]
  (** Server name and version. *)
end

(** Root directory information. *)
module Root : sig
  type t = {
    uri : string;
    name : string option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Root directory URI with optional name. *)
end

(** Sampling message for model interactions. *)
module SamplingMessage : sig
  type t = { role : string; content : Content.t }
  [@@deriving yojson { strict = false }]
  (** Message with role and content for sampling. *)
end

(** Model hint for sampling. *)
module ModelHint : sig
  type t = { name : string option } [@@deriving yojson { strict = false }]
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
  [@@deriving yojson { strict = false }]
  (** Preferences for model selection with priority weights. *)
end

(** Completion argument specification. *)
module CompletionArgument : sig
  type t = { name : string; value : string }
  [@@deriving yojson { strict = false }]
  (** Named argument with value. *)
end

(** Completion reference types. *)
module CompletionReference : sig
  (** Reference to completable items by type and name. *)
  type t = Resource of string | ResourceTemplate of string | Prompt of string
  [@@deriving yojson { strict = false }]
end

(** Completion result with pagination. *)
module Completion : sig
  type t = { values : string list; total : int option; has_more : bool option }
  [@@deriving yojson { strict = false }]
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
  [@@deriving yojson { strict = false }]

  type number_schema = {
    type_ : string;
    title : string option;
    description : string option;
    minimum : int option;
    maximum : int option;
  }
  [@@deriving yojson { strict = false }]

  type boolean_schema = {
    type_ : string;
    title : string option;
    description : string option;
    default : bool option;
  }
  [@@deriving yojson { strict = false }]

  type enum_schema = {
    type_ : string;
    title : string option;
    description : string option;
    enum : string list;
    enum_names : string list option;
  }
  [@@deriving yojson { strict = false }]

  type t =
    | String of string_schema
    | Number of number_schema
    | Boolean of boolean_schema
    | Enum of enum_schema
  [@@deriving yojson { strict = false }]
end

(** Elicitation schema for structured input. *)
module ElicitationSchema : sig
  type t = {
    type_ : string;
    properties : (string * PrimitiveSchema.t) list;
    required : string list;
  }

  val to_yojson : t -> Yojson.Safe.t
  val of_yojson : Yojson.Safe.t -> (t, string) result
end
