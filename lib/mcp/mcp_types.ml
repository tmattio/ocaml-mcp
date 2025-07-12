module Protocol = struct
  let latest_version = "2025-06-18"
  let default_negotiated_version = "2025-03-26"

  let supported_versions =
    [ "2025-06-18"; "2025-03-26"; "2024-11-05"; "2024-10-07" ]

  let jsonrpc_version = "2.0"
end

type request_id = String of string | Int of int [@@deriving yojson]
type progress_token = String of string | Int of int [@@deriving yojson]
type cursor = string [@@deriving yojson]

module ErrorCode = struct
  type t = int [@@deriving yojson]

  let connection_closed = -32000
  let request_timeout = -32001
  let parse_error = -32700
  let invalid_request = -32600
  let method_not_found = -32601
  let invalid_params = -32602
  let internal_error = -32603
end

type error = {
  code : ErrorCode.t;
  message : string;
  data : Yojson.Safe.t option; [@default None]
}
[@@deriving yojson]

type meta = Yojson.Safe.t [@@deriving yojson]

type 'a with_meta = {
  result : 'a; [@key "_result"]
  meta : meta option; [@default None] [@key "_meta"]
}
[@@deriving yojson]

module LogLevel = struct
  type t =
    | Debug [@name "debug"]
    | Info [@name "info"]
    | Notice [@name "notice"]
    | Warning [@name "warning"]
    | Error [@name "error"]
    | Critical [@name "critical"]
    | Alert [@name "alert"]
    | Emergency [@name "emergency"]
  [@@deriving yojson]
end

module Content = struct
  type text = { type_ : string; [@key "type"] text : string }
  [@@deriving yojson]

  type image = {
    type_ : string; [@key "type"]
    data : string;
    mime_type : string; [@key "mimeType"]
  }
  [@@deriving yojson]

  type audio = {
    type_ : string; [@key "type"]
    data : string;
    mime_type : string; [@key "mimeType"]
  }
  [@@deriving yojson]

  type resource_link = {
    type_ : string; [@key "type"]
    uri : string;
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    mime_type : string option; [@default None] [@key "mimeType"]
    size : int option; [@default None]
    annotations : Yojson.Safe.t option; [@default None]
  }
  [@@deriving yojson]

  type resource_contents = {
    uri : string;
    mime_type : string option; [@default None] [@key "mimeType"]
    text : string option; [@default None]
    blob : string option; [@default None]
  }
  [@@deriving yojson]

  type embedded_resource = {
    type_ : string; [@key "type"]
    resource : resource_contents;
  }
  [@@deriving yojson]

  type t =
    | Text of text
    | Image of image
    | Audio of audio
    | ResourceLink of resource_link
    | EmbeddedResource of embedded_resource

  let to_yojson = function
    | Text t -> text_to_yojson t
    | Image i -> image_to_yojson i
    | Audio a -> audio_to_yojson a
    | ResourceLink r -> resource_link_to_yojson r
    | EmbeddedResource e -> embedded_resource_to_yojson e

  let of_yojson json =
    match json with
    | `Assoc fields -> (
        match Stdlib.List.assoc_opt "type" fields with
        | Some (`String "text") ->
            text_of_yojson json |> Result.map (fun t -> Text t)
        | Some (`String "image") ->
            image_of_yojson json |> Result.map (fun i -> Image i)
        | Some (`String "audio") ->
            audio_of_yojson json |> Result.map (fun a -> Audio a)
        | Some (`String "resource_link") ->
            resource_link_of_yojson json |> Result.map (fun r -> ResourceLink r)
        | Some (`String "resource") ->
            embedded_resource_of_yojson json
            |> Result.map (fun e -> EmbeddedResource e)
        | Some (`String t) -> Error ("Unknown content type: " ^ t)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
    | _ -> Error "Content must be an object"
end

module Resource = struct
  type t = {
    uri : string;
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    mime_type : string option; [@default None] [@key "mimeType"]
    size : int option; [@default None]
    annotations : Yojson.Safe.t option; [@default None]
  }
  [@@deriving yojson]

  type template = {
    uri_template : string; [@key "uriTemplate"]
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    mime_type : string option; [@default None] [@key "mimeType"]
    annotations : Yojson.Safe.t option; [@default None]
  }
  [@@deriving yojson]
end

module Tool = struct
  type annotation = {
    title : string option; [@default None]
    read_only : bool option; [@default None] [@key "readOnlyHint"]
    destructive : bool option; [@default None] [@key "destructiveHint"]
    idempotent : bool option; [@default None] [@key "idempotentHint"]
    open_world : bool option; [@default None] [@key "openWorldHint"]
  }
  [@@deriving yojson]

  type t = {
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    input_schema : Yojson.Safe.t; [@key "inputSchema"]
    output_schema : Yojson.Safe.t option; [@default None] [@key "outputSchema"]
    annotations : annotation option; [@default None]
  }
  [@@deriving yojson]
end

module Prompt = struct
  type argument = {
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    required : bool option; [@default None]
  }
  [@@deriving yojson]

  type t = {
    name : string;
    title : string option; [@default None]
    description : string option; [@default None]
    arguments : argument list option; [@default None]
  }
  [@@deriving yojson]

  type message = { role : string; content : Content.t } [@@deriving yojson]
end

module Capabilities = struct
  type roots = {
    list_changed : bool option; [@default None] [@key "listChanged"]
  }
  [@@deriving yojson]

  type prompts = { list_changed : bool option [@key "listChanged"] }
  [@@deriving yojson]

  type resources = {
    subscribe : bool option;
    list_changed : bool option; [@key "listChanged"]
  }
  [@@deriving yojson]

  type tools = { list_changed : bool option [@key "listChanged"] }
  [@@deriving yojson]

  type client = {
    experimental : Yojson.Safe.t option; [@default None]
    sampling : Yojson.Safe.t option; [@default None]
    elicitation : Yojson.Safe.t option; [@default None]
    roots : roots option; [@default None]
  }
  [@@deriving yojson]

  type server = {
    experimental : Yojson.Safe.t option; [@default None]
    logging : Yojson.Safe.t option; [@default None]
    completions : Yojson.Safe.t option; [@default None]
    prompts : prompts option; [@default None]
    resources : resources option; [@default None]
    tools : tools option; [@default None]
  }
  [@@deriving yojson]
end

module Implementation = struct
  type t = { name : string; version : string } [@@deriving yojson]
end

module ClientInfo = struct
  type t = { name : string; version : string } [@@deriving yojson]
end

module ServerInfo = struct
  type t = { name : string; version : string } [@@deriving yojson]
end

module Root = struct
  type t = { uri : string; name : string option [@default None] }
  [@@deriving yojson]
end

module SamplingMessage = struct
  type t = { role : string; content : Content.t } [@@deriving yojson]
end

module ModelHint = struct
  type t = { name : string option [@default None] } [@@deriving yojson]
end

module ModelPreferences = struct
  type t = {
    hints : ModelHint.t list option; [@default None]
    cost_priority : float option; [@default None] [@key "costPriority"]
    speed_priority : float option; [@default None] [@key "speedPriority"]
    intelligence_priority : float option;
        [@default None] [@key "intelligencePriority"]
  }
  [@@deriving yojson]
end

module CompletionArgument = struct
  type t = { name : string; value : string } [@@deriving yojson]
end

module CompletionReference = struct
  type t = Resource of string | ResourceTemplate of string | Prompt of string

  let to_yojson = function
    | Resource uri ->
        `Assoc [ ("type", `String "ref/resource"); ("uri", `String uri) ]
    | ResourceTemplate uri ->
        `Assoc [ ("type", `String "ref/resource"); ("uri", `String uri) ]
    | Prompt name ->
        `Assoc [ ("type", `String "ref/prompt"); ("name", `String name) ]

  let of_yojson = function
    | `Assoc fields -> (
        match Stdlib.List.assoc_opt "type" fields with
        | Some (`String "ref/resource") -> (
            match Stdlib.List.assoc_opt "uri" fields with
            | Some (`String uri) -> Ok (Resource uri)
            | _ -> Error "Missing or invalid uri field")
        | Some (`String "ref/prompt") -> (
            match Stdlib.List.assoc_opt "name" fields with
            | Some (`String name) -> Ok (Prompt name)
            | _ -> Error "Missing or invalid name field")
        | Some (`String t) -> Error ("Unknown reference type: " ^ t)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
    | _ -> Error "CompletionReference must be an object"
end

module Completion = struct
  type t = {
    values : string list;
    total : int option; [@default None]
    has_more : bool option; [@default None] [@key "hasMore"]
  }
  [@@deriving yojson]
end

module PrimitiveSchema = struct
  type string_schema = {
    type_ : string; [@key "type"]
    title : string option; [@default None]
    description : string option; [@default None]
    format : string option; [@default None]
    min_length : int option; [@default None] [@key "minLength"]
    max_length : int option; [@default None] [@key "maxLength"]
  }
  [@@deriving yojson]

  type number_schema = {
    type_ : string; [@key "type"]
    title : string option; [@default None]
    description : string option; [@default None]
    minimum : int option; [@default None]
    maximum : int option; [@default None]
  }
  [@@deriving yojson]

  type boolean_schema = {
    type_ : string; [@key "type"]
    title : string option; [@default None]
    description : string option; [@default None]
    default : bool option; [@default None]
  }
  [@@deriving yojson]

  type enum_schema = {
    type_ : string; [@key "type"]
    title : string option; [@default None]
    description : string option; [@default None]
    enum : string list; [@key "enum"]
    enum_names : string list option; [@default None] [@key "enumNames"]
  }
  [@@deriving yojson]

  type t =
    | String of string_schema
    | Number of number_schema
    | Boolean of boolean_schema
    | Enum of enum_schema

  let to_yojson = function
    | String s -> string_schema_to_yojson s
    | Number n -> number_schema_to_yojson n
    | Boolean b -> boolean_schema_to_yojson b
    | Enum e -> enum_schema_to_yojson e

  let of_yojson json =
    match json with
    | `Assoc fields -> (
        match Stdlib.List.assoc_opt "type" fields with
        | Some (`String "string") -> (
            match Stdlib.List.assoc_opt "enum" fields with
            | Some _ ->
                enum_schema_of_yojson json |> Result.map (fun e -> Enum e)
            | None ->
                string_schema_of_yojson json |> Result.map (fun s -> String s))
        | Some (`String ("integer" | "number")) ->
            number_schema_of_yojson json |> Result.map (fun n -> Number n)
        | Some (`String "boolean") ->
            boolean_schema_of_yojson json |> Result.map (fun b -> Boolean b)
        | Some (`String t) -> Error ("Unknown schema type: " ^ t)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
    | _ -> Error "Schema must be an object"
end

module ElicitationSchema = struct
  type t = {
    type_ : string; [@key "type"]
    properties : (string * PrimitiveSchema.t) list; [@key "properties"]
    required : string list; [@key "required"]
  }

  let to_yojson schema =
    let properties_json =
      Stdlib.List.map
        (fun (k, v) -> (k, PrimitiveSchema.to_yojson v))
        schema.properties
    in
    `Assoc
      [
        ("type", `String schema.type_);
        ("properties", `Assoc properties_json);
        ("required", `List (List.map (fun s -> `String s) schema.required));
      ]

  let of_yojson = function
    | `Assoc fields -> (
        match
          ( List.assoc_opt "type" fields,
            List.assoc_opt "properties" fields,
            List.assoc_opt "required" fields )
        with
        | Some (`String "object"), Some (`Assoc props), Some (`List req) -> (
            let parse_props =
              Stdlib.List.fold_left
                (fun acc (k, v) ->
                  match acc with
                  | Error _ -> acc
                  | Ok props -> (
                      match PrimitiveSchema.of_yojson v with
                      | Ok schema -> Ok ((k, schema) :: props)
                      | Error e -> Error e))
                (Ok []) props
            in
            let parse_required =
              Stdlib.List.fold_left
                (fun acc r ->
                  match acc with
                  | Error _ -> acc
                  | Ok reqs -> (
                      match r with
                      | `String s -> Ok (s :: reqs)
                      | _ -> Error "required must be array of strings"))
                (Ok []) req
            in
            match (parse_props, parse_required) with
            | Ok props, Ok reqs ->
                Ok
                  {
                    type_ = "object";
                    properties = Stdlib.List.rev props;
                    required = Stdlib.List.rev reqs;
                  }
            | Error e, _ | _, Error e -> Error e)
        | _ -> Error "Invalid elicitation schema")
    | _ -> Error "ElicitationSchema must be an object"
end
