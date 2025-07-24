(** MCP request types and handlers.

    This module defines all request types in the Model Context Protocol,
    including their parameters and result types. Each request follows the
    JSON-RPC format with typed parameters and results. *)

open Mcp_types

(** Initialization handshake. *)
module Initialize : sig
  type params = {
    protocol_version : string;
    capabilities : Capabilities.client;
    client_info : ClientInfo.t;
  }
  [@@deriving yojson { strict = false }]
  (** Initialization parameters with version and capabilities. *)

  type result = {
    protocol_version : string;
    capabilities : Capabilities.server;
    server_info : ServerInfo.t;
    instructions : string option;
    meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
  }
  [@@deriving yojson { strict = false }]
  (** Initialization result with negotiated version and server info. *)
end

(** Resource discovery and reading. *)
module Resources : sig
  module List : sig
    type params = {
      cursor : cursor option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      resources : Resource.t list;
      next_cursor : cursor option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Read : sig
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      contents : Content.resource_contents list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Subscribe : sig
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = unit [@@deriving yojson { strict = false }]
  end

  module Unsubscribe : sig
    type params = {
      uri : string;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = unit [@@deriving yojson { strict = false }]
  end

  module Templates : sig
    module List : sig
      type params = {
        cursor : cursor option;
        meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
      }
      [@@deriving yojson { strict = false }]

      type result = {
        resource_templates : Resource.template list;
        next_cursor : cursor option;
        meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
      }
      [@@deriving yojson { strict = false }]
    end
  end
end

(** Prompt template management. *)
module Prompts : sig
  module List : sig
    type params = {
      cursor : cursor option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      prompts : Prompt.t list;
      next_cursor : cursor option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Get : sig
    type params = {
      name : string;
      arguments : (string * string) list option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    val params_to_yojson : params -> Yojson.Safe.t
    val params_of_yojson : Yojson.Safe.t -> (params, string) Stdlib.result

    type result = {
      description : string option;
      messages : Prompt.message list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

(** Tool discovery and invocation. *)
module Tools : sig
  module List : sig
    type params = {
      cursor : cursor option; [@default None]
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      tools : Tool.t list;
      next_cursor : cursor option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end

  module Call : sig
    type params = {
      name : string;
      arguments : Yojson.Safe.t option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      content : Content.t list;
      is_error : bool option;
      structured_content : Yojson.Safe.t option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

(** LLM sampling requests. *)
module Sampling : sig
  module CreateMessage : sig
    type params = {
      messages : SamplingMessage.t list;
      model_preferences : ModelPreferences.t option;
      system_prompt : string option;
      include_context : string option;
      temperature : float option;
      max_tokens : int option;
      stop_sequences : string list option;
      metadata : Yojson.Safe.t option;
    }
    [@@deriving yojson { strict = false }]

    type result = {
      role : string;
      content : Content.t;
      model : string;
      stop_reason : string option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

(** User input elicitation. *)
module Elicitation : sig
  module Create : sig
    type params = {
      message : string;
      requested_schema : ElicitationSchema.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    val params_to_yojson : params -> Yojson.Safe.t
    val params_of_yojson : Yojson.Safe.t -> (params, string) Stdlib.result

    type result = {
      action : string;
      content : (string * Yojson.Safe.t) list option;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }

    val result_to_yojson : result -> Yojson.Safe.t
    val result_of_yojson : Yojson.Safe.t -> (result, string) Stdlib.result
  end
end

(** Logging configuration. *)
module Logging : sig
  module SetLevel : sig
    type params = {
      level : LogLevel.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  end
end

(** Argument completion. *)
module Completion : sig
  module Complete : sig
    type params = {
      ref_ : CompletionReference.t;
      argument : CompletionArgument.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]

    type result = {
      completion : Completion.t;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

(** Root directory listing. *)
module Roots : sig
  module List : sig
    type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]

    type result = {
      roots : Root.t list;
      meta : Yojson.Safe.t option; [@default None] [@key "_meta"]
    }
    [@@deriving yojson { strict = false }]
  end
end

(** Connection keep-alive. *)
module Ping : sig
  type params = OnlyMetaParams.t [@@deriving yojson { strict = false }]
  type result = unit [@@deriving yojson { strict = false }]
end

type t =
  | Initialize of Initialize.params
  | ResourcesList of Resources.List.params
  | ResourcesRead of Resources.Read.params
  | ResourcesSubscribe of Resources.Subscribe.params
  | ResourcesUnsubscribe of Resources.Unsubscribe.params
  | ResourcesTemplatesList of Resources.Templates.List.params
  | PromptsList of Prompts.List.params
  | PromptsGet of Prompts.Get.params
  | ToolsList of Tools.List.params
  | ToolsCall of Tools.Call.params
  | SamplingCreateMessage of Sampling.CreateMessage.params
  | ElicitationCreate of Elicitation.Create.params
  | LoggingSetLevel of Logging.SetLevel.params
  | CompletionComplete of Completion.Complete.params
  | RootsList of Roots.List.params
  | Ping of Ping.params  (** Request variants for all MCP methods. *)

val method_name : t -> string
(** [method_name request] returns JSON-RPC method name. *)

val params_to_yojson : t -> Yojson.Safe.t
(** [params_to_yojson request] converts parameters to JSON. *)

val of_jsonrpc : string -> Yojson.Safe.t option -> (t, string) result
(** [of_jsonrpc method params] parses JSON-RPC into typed request.

    @param method JSON-RPC method name
    @param params optional parameters
    @return Ok with typed request or Error with description *)

type response =
  | Initialize of Initialize.result
  | ResourcesList of Resources.List.result
  | ResourcesRead of Resources.Read.result
  | ResourcesSubscribe of Resources.Subscribe.result
  | ResourcesUnsubscribe of Resources.Unsubscribe.result
  | ResourcesTemplatesList of Resources.Templates.List.result
  | PromptsList of Prompts.List.result
  | PromptsGet of Prompts.Get.result
  | ToolsList of Tools.List.result
  | ToolsCall of Tools.Call.result
  | SamplingCreateMessage of Sampling.CreateMessage.result
  | ElicitationCreate of Elicitation.Create.result
  | LoggingSetLevel of Logging.SetLevel.result
  | CompletionComplete of Completion.Complete.result
  | RootsList of Roots.List.result
  | Ping of Ping.result  (** Response variants for all MCP methods. *)

val response_to_yojson : response -> Yojson.Safe.t
(** [response_to_yojson response] converts result to JSON. *)
