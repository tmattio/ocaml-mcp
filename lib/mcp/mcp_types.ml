module Json_codec = struct
  let decode = Jsont.Json.decode

  let encode codec value =
    match Jsont.Json.encode codec value with
    | Ok json -> json
    | Error message -> Jsont.Error.msgf Jsont.Meta.none "%s" message

  let map ~dec ~enc =
    Jsont.map Jsont.json
      ~dec:(fun json ->
        match dec json with
        | Ok value -> value
        | Error message -> Jsont.Error.msgf (Jsont.Json.meta json) "%s" message)
      ~enc

  (* Generic JSON numbers use IEEE 754 doubles. Reject ambiguous integers
     rather than changing an identifier or count during a round trip. *)
  let integer_json =
    let valid n =
      Float.is_finite n
      && Float.floor n = n
      && Float.abs n <= 9007199254740991.
      && n >= float_of_int min_int
      && n <= float_of_int max_int
    in
    Jsont.Base.number
      (Jsont.Base.map ~kind:"integer"
         ~dec:(fun meta n ->
           if valid n then int_of_float n
           else
             Jsont.Error.msgf meta "Expected an exactly representable integer")
         ~enc:(fun n ->
           let number = float_of_int n in
           if valid number then number
           else
             Jsont.Error.msgf Jsont.Meta.none
               "Integer exceeds the exact JSON number range")
         ())

  let number_json =
    Jsont.Base.number
      (Jsont.Base.map ~kind:"finite number"
         ~dec:(fun meta n ->
           if Float.is_finite n then n
           else Jsont.Error.msgf meta "Expected a finite number")
         ~enc:(fun n ->
           if Float.is_finite n then n
           else Jsont.Error.msgf Jsont.Meta.none "Expected a finite number")
         ())

  let assoc_json value_json =
    let members =
      Jsont.Object.Mems.map value_json
        ~dec_empty:(fun () -> [])
        ~dec_add:(fun _ name value values -> (name, value) :: values)
        ~dec_finish:(fun _ values -> List.rev values)
        ~enc:
          {
            enc =
              (fun add values acc ->
                List.fold_left
                  (fun acc (name, value) -> add Jsont.Meta.none name value acc)
                  acc values);
          }
    in
    Jsont.Object.map Fun.id
    |> Jsont.Object.keep_unknown members ~enc:Fun.id
    |> Jsont.Object.finish

  let find_member name = function
    | Jsont.Object (members, _) ->
        Option.map snd (Jsont.Json.find_mem name members)
    | _ -> None

  let object' members =
    Jsont.Json.object'
      (List.map
         (fun (name, value) -> Jsont.Json.mem (name, Jsont.Meta.none) value)
         members)

  (* The handwritten parsers used List.assoc_opt, which selects the first
     occurrence. Keep that rule while using typed object codecs. *)
  let first_object codec =
    let first_members = function
      | Jsont.Object (members, meta) ->
          let names = Hashtbl.create 16 in
          let keep ((name, _), _) =
            if Hashtbl.mem names name then false
            else (
              Hashtbl.add names name ();
              true)
          in
          Jsont.Object (List.filter keep members, meta)
      | value -> value
    in
    map
      ~dec:(fun value -> decode codec (first_members value))
      ~enc:(encode codec)

  (* Generated record decoders selected the last occurrence before reporting
     errors, including when an earlier duplicate had the wrong type. *)
  let last_object codec =
    let last_members = function
      | Jsont.Object (members, meta) ->
          let names = Hashtbl.create 16 in
          let keep ((name, _), _) =
            if Hashtbl.mem names name then false
            else (
              Hashtbl.add names name ();
              true)
          in
          let members = List.rev (List.filter keep (List.rev members)) in
          Jsont.Object (members, meta)
      | value -> value
    in
    map
      ~dec:(fun value -> decode codec (last_members value))
      ~enc:(encode codec)
end

module Protocol = struct
  let latest_version = "2025-06-18"
  let default_negotiated_version = "2025-03-26"

  let supported_versions =
    [ "2025-06-18"; "2025-03-26"; "2024-11-05"; "2024-10-07" ]

  let jsonrpc_version = "2.0"
end

type request_id = String of string | Int of int

let request_id_json : request_id Jsont.t =
  let string =
    Jsont.map Jsont.string
      ~dec:(fun s -> (String s : request_id))
      ~enc:(function String s -> s | _ -> assert false)
  in
  let integer =
    Jsont.map Json_codec.integer_json
      ~dec:(fun i -> (Int i : request_id))
      ~enc:(function Int i -> i | _ -> assert false)
  in
  Jsont.any ~dec_string:string ~dec_number:integer
    ~enc:(function String _ -> string | Int _ -> integer)
    ()

type progress_token = String of string | Int of int

let progress_token_json : progress_token Jsont.t =
  let string =
    Jsont.map Jsont.string
      ~dec:(fun s -> (String s : progress_token))
      ~enc:(function String s -> s | _ -> assert false)
  in
  let integer =
    Jsont.map Json_codec.integer_json
      ~dec:(fun i -> (Int i : progress_token))
      ~enc:(function Int i -> i | _ -> assert false)
  in
  Jsont.any ~dec_string:string ~dec_number:integer
    ~enc:(function String _ -> string | Int _ -> integer)
    ()

type cursor = string

let cursor_json = Jsont.string

module ErrorCode = struct
  type t = int

  let json = Json_codec.integer_json
  let connection_closed = -32000
  let request_timeout = -32001
  let parse_error = -32700
  let invalid_request = -32600
  let method_not_found = -32601
  let invalid_params = -32602
  let internal_error = -32603
end

type error = { code : ErrorCode.t; message : string; data : Jsont.json option }

let error_json : error Jsont.t =
  Jsont.Object.map (fun code message data -> ({ code; message; data } : error))
  |> Jsont.Object.mem "code" ErrorCode.json ~enc:(fun (v : error) -> v.code)
  |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (v : error) -> v.message)
  |> Jsont.Object.mem "data" (Jsont.option Jsont.json) ~dec_absent:None
       ~enc_omit:Option.is_none ~enc:(fun (v : error) -> v.data)
  |> Jsont.Object.finish |> Json_codec.last_object

module OnlyMetaParams = struct
  type t = { meta : Jsont.json option }

  let json : t Jsont.t =
    let object_json =
      Jsont.Object.map (fun meta -> { meta })
      |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
           ~enc_omit:Option.is_none ~enc:(fun v -> v.meta)
      |> Jsont.Object.finish |> Json_codec.last_object
    in
    Json_codec.map
      ~dec:(fun value ->
        match Json_codec.decode object_json value with
        | Ok params -> Ok params
        | Error _ -> Ok { meta = None })
      ~enc:(Json_codec.encode object_json)
end

module LogLevel = struct
  type t =
    | Debug
    | Info
    | Notice
    | Warning
    | Error
    | Critical
    | Alert
    | Emergency

  let json =
    Jsont.enum
      [
        ("debug", Debug);
        ("info", Info);
        ("notice", Notice);
        ("warning", Warning);
        ("error", Error);
        ("critical", Critical);
        ("alert", Alert);
        ("emergency", Emergency);
      ]
end

module Content = struct
  type text = { type_ : string; text : string; meta : Jsont.json option }

  let text_json : text Jsont.t =
    Jsont.Object.map (fun type_ text meta -> ({ type_; text; meta } : text))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : text) -> v.type_)
    |> Jsont.Object.mem "text" Jsont.string ~enc:(fun (v : text) -> v.text)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : text) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type image = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Jsont.json option;
  }

  let image_json : image Jsont.t =
    Jsont.Object.map (fun type_ data mime_type meta ->
        ({ type_; data; mime_type; meta } : image))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : image) -> v.type_)
    |> Jsont.Object.mem "data" Jsont.string ~enc:(fun (v : image) -> v.data)
    |> Jsont.Object.mem "mimeType" Jsont.string ~enc:(fun (v : image) ->
        v.mime_type)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : image) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type audio = {
    type_ : string;
    data : string;
    mime_type : string;
    meta : Jsont.json option;
  }

  let audio_json : audio Jsont.t =
    Jsont.Object.map (fun type_ data mime_type meta ->
        ({ type_; data; mime_type; meta } : audio))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : audio) -> v.type_)
    |> Jsont.Object.mem "data" Jsont.string ~enc:(fun (v : audio) -> v.data)
    |> Jsont.Object.mem "mimeType" Jsont.string ~enc:(fun (v : audio) ->
        v.mime_type)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : audio) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

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

  let resource_link_json : resource_link Jsont.t =
    Jsont.Object.map
      (fun type_ uri name title description mime_type size annotations meta ->
        ({
           type_;
           uri;
           name;
           title;
           description;
           mime_type;
           size;
           annotations;
           meta;
         }
          : resource_link))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : resource_link) ->
        v.type_)
    |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : resource_link) ->
        v.uri)
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : resource_link) ->
        v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_link) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_link) -> v.description)
    |> Jsont.Object.mem "mimeType" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_link) -> v.mime_type)
    |> Jsont.Object.mem "size" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_link) -> v.size)
    |> Jsont.Object.mem "annotations" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : resource_link) ->
           v.annotations)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : resource_link) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type resource_contents = {
    uri : string;
    mime_type : string option;
    text : string option;
    blob : string option;
    meta : Jsont.json option;
  }

  let resource_contents_json : resource_contents Jsont.t =
    Jsont.Object.map (fun uri mime_type text blob meta ->
        ({ uri; mime_type; text; blob; meta } : resource_contents))
    |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : resource_contents) ->
        v.uri)
    |> Jsont.Object.mem "mimeType" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_contents) -> v.mime_type)
    |> Jsont.Object.mem "text" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_contents) -> v.text)
    |> Jsont.Object.mem "blob" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : resource_contents) -> v.blob)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : resource_contents) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type embedded_resource = {
    type_ : string;
    resource : resource_contents;
    meta : Jsont.json option;
  }

  let embedded_resource_json : embedded_resource Jsont.t =
    Jsont.Object.map (fun type_ resource meta ->
        ({ type_; resource; meta } : embedded_resource))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : embedded_resource) ->
        v.type_)
    |> Jsont.Object.mem "resource" resource_contents_json
         ~enc:(fun (v : embedded_resource) -> v.resource)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : embedded_resource) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type t =
    | Text of text
    | Image of image
    | Audio of audio
    | ResourceLink of resource_link
    | EmbeddedResource of embedded_resource

  let json : t Jsont.t =
    Json_codec.map
      ~enc:(function
        | Text value -> Json_codec.encode text_json value
        | Image value -> Json_codec.encode image_json value
        | Audio value -> Json_codec.encode audio_json value
        | ResourceLink value -> Json_codec.encode resource_link_json value
        | EmbeddedResource value ->
            Json_codec.encode embedded_resource_json value)
      ~dec:(fun value ->
        match Json_codec.find_member "type" value with
        | Some (Jsont.String ("text", _)) ->
            Json_codec.decode text_json value |> Result.map (fun v -> Text v)
        | Some (Jsont.String ("image", _)) ->
            Json_codec.decode image_json value |> Result.map (fun v -> Image v)
        | Some (Jsont.String ("audio", _)) ->
            Json_codec.decode audio_json value |> Result.map (fun v -> Audio v)
        | Some (Jsont.String ("resource_link", _)) ->
            Json_codec.decode resource_link_json value
            |> Result.map (fun v -> ResourceLink v)
        | Some (Jsont.String ("resource", _)) ->
            Json_codec.decode embedded_resource_json value
            |> Result.map (fun v -> EmbeddedResource v)
        | Some (Jsont.String (kind, _)) ->
            Error ("Unknown content type: " ^ kind)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
end

module Resource = struct
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

  let json : t Jsont.t =
    Jsont.Object.map
      (fun uri name title description mime_type size annotations meta ->
        ({ uri; name; title; description; mime_type; size; annotations; meta }
          : t))
    |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : t) -> v.uri)
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.description)
    |> Jsont.Object.mem "mimeType" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.mime_type)
    |> Jsont.Object.mem "size" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.size)
    |> Jsont.Object.mem "annotations" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.annotations)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type template = {
    uri_template : string;
    name : string;
    title : string option;
    description : string option;
    mime_type : string option;
    annotations : Jsont.json option;
    meta : Jsont.json option;
  }

  let template_json : template Jsont.t =
    Jsont.Object.map
      (fun uri_template name title description mime_type annotations meta ->
        ({
           uri_template;
           name;
           title;
           description;
           mime_type;
           annotations;
           meta;
         }
          : template))
    |> Jsont.Object.mem "uriTemplate" Jsont.string ~enc:(fun (v : template) ->
        v.uri_template)
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : template) -> v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : template) ->
           v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : template) ->
           v.description)
    |> Jsont.Object.mem "mimeType" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : template) ->
           v.mime_type)
    |> Jsont.Object.mem "annotations" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : template) -> v.annotations)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : template) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Tool = struct
  type annotation = {
    title : string option;
    read_only : bool option;
    destructive : bool option;
    idempotent : bool option;
    open_world : bool option;
  }

  let annotation_json : annotation Jsont.t =
    Jsont.Object.map (fun title read_only destructive idempotent open_world ->
        ({ title; read_only; destructive; idempotent; open_world } : annotation))
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : annotation) ->
           v.title)
    |> Jsont.Object.mem "readOnlyHint" (Jsont.option Jsont.bool)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : annotation) ->
           v.read_only)
    |> Jsont.Object.mem "destructiveHint" (Jsont.option Jsont.bool)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : annotation) ->
           v.destructive)
    |> Jsont.Object.mem "idempotentHint" (Jsont.option Jsont.bool)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : annotation) ->
           v.idempotent)
    |> Jsont.Object.mem "openWorldHint" (Jsont.option Jsont.bool)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : annotation) ->
           v.open_world)
    |> Jsont.Object.finish |> Json_codec.last_object

  type t = {
    name : string;
    title : string option;
    description : string option;
    input_schema : Jsont.json;
    output_schema : Jsont.json option;
    annotations : annotation option;
    meta : Jsont.json option;
  }

  let json : t Jsont.t =
    Jsont.Object.map
      (fun name title description input_schema output_schema annotations meta ->
        ({
           name;
           title;
           description;
           input_schema;
           output_schema;
           annotations;
           meta;
         }
          : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.description)
    |> Jsont.Object.mem "inputSchema" Jsont.json ~enc:(fun (v : t) ->
        v.input_schema)
    |> Jsont.Object.mem "outputSchema" (Jsont.option Jsont.json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.output_schema)
    |> Jsont.Object.mem "annotations" (Jsont.option annotation_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.annotations)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Prompt = struct
  type argument = {
    name : string;
    title : string option;
    description : string option;
    required : bool option;
  }

  let argument_json : argument Jsont.t =
    Jsont.Object.map (fun name title description required ->
        ({ name; title; description; required } : argument))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : argument) -> v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : argument) ->
           v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : argument) ->
           v.description)
    |> Jsont.Object.mem "required" (Jsont.option Jsont.bool) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : argument) -> v.required)
    |> Jsont.Object.finish |> Json_codec.last_object

  type t = {
    name : string;
    title : string option;
    description : string option;
    arguments : argument list option;
    meta : Jsont.json option;
  }

  let json : t Jsont.t =
    Jsont.Object.map (fun name title description arguments meta ->
        ({ name; title; description; arguments; meta } : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.description)
    |> Jsont.Object.mem "arguments"
         (Jsont.option (Jsont.list argument_json))
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : t) -> v.arguments)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object

  type message = { role : string; content : Content.t }

  let message_json : message Jsont.t =
    Jsont.Object.map (fun role content -> ({ role; content } : message))
    |> Jsont.Object.mem "role" Jsont.string ~enc:(fun (v : message) -> v.role)
    |> Jsont.Object.mem "content" Content.json ~enc:(fun (v : message) ->
        v.content)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Capabilities = struct
  type roots = { list_changed : bool option }

  let roots_json : roots Jsont.t =
    Jsont.Object.map (fun list_changed -> ({ list_changed } : roots))
    |> Jsont.Object.mem "listChanged" (Jsont.option Jsont.bool) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : roots) -> v.list_changed)
    |> Jsont.Object.finish |> Json_codec.last_object

  type prompts = { list_changed : bool option }

  let prompts_json : prompts Jsont.t =
    Jsont.Object.map (fun list_changed -> ({ list_changed } : prompts))
    |> Jsont.Object.mem "listChanged" (Jsont.option Jsont.bool)
         ~enc:(fun (v : prompts) -> v.list_changed)
    |> Jsont.Object.finish |> Json_codec.last_object

  type resources = { subscribe : bool option; list_changed : bool option }

  let resources_json : resources Jsont.t =
    Jsont.Object.map (fun subscribe list_changed ->
        ({ subscribe; list_changed } : resources))
    |> Jsont.Object.mem "subscribe" (Jsont.option Jsont.bool)
         ~enc:(fun (v : resources) -> v.subscribe)
    |> Jsont.Object.mem "listChanged" (Jsont.option Jsont.bool)
         ~enc:(fun (v : resources) -> v.list_changed)
    |> Jsont.Object.finish |> Json_codec.last_object

  type tools = { list_changed : bool option }

  let tools_json : tools Jsont.t =
    Jsont.Object.map (fun list_changed -> ({ list_changed } : tools))
    |> Jsont.Object.mem "listChanged" (Jsont.option Jsont.bool)
         ~enc:(fun (v : tools) -> v.list_changed)
    |> Jsont.Object.finish |> Json_codec.last_object

  type client = {
    experimental : Jsont.json option;
    sampling : Jsont.json option;
    elicitation : Jsont.json option;
    roots : roots option;
  }

  let client_json : client Jsont.t =
    Jsont.Object.map (fun experimental sampling elicitation roots ->
        ({ experimental; sampling; elicitation; roots } : client))
    |> Jsont.Object.mem "experimental" (Jsont.option Jsont.json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : client) ->
           v.experimental)
    |> Jsont.Object.mem "sampling" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : client) -> v.sampling)
    |> Jsont.Object.mem "elicitation" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : client) -> v.elicitation)
    |> Jsont.Object.mem "roots" (Jsont.option roots_json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : client) -> v.roots)
    |> Jsont.Object.finish |> Json_codec.last_object

  type server = {
    experimental : Jsont.json option;
    logging : Jsont.json option;
    completions : Jsont.json option;
    prompts : prompts option;
    resources : resources option;
    tools : tools option;
  }

  let server_json : server Jsont.t =
    Jsont.Object.map
      (fun experimental logging completions prompts resources tools ->
        ({ experimental; logging; completions; prompts; resources; tools }
          : server))
    |> Jsont.Object.mem "experimental" (Jsont.option Jsont.json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : server) ->
           v.experimental)
    |> Jsont.Object.mem "logging" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : server) -> v.logging)
    |> Jsont.Object.mem "completions" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : server) -> v.completions)
    |> Jsont.Object.mem "prompts" (Jsont.option prompts_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : server) ->
           v.prompts)
    |> Jsont.Object.mem "resources" (Jsont.option resources_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : server) ->
           v.resources)
    |> Jsont.Object.mem "tools" (Jsont.option tools_json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : server) -> v.tools)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Implementation = struct
  type t = { name : string; version : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun name version -> ({ name; version } : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "version" Jsont.string ~enc:(fun (v : t) -> v.version)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module ClientInfo = struct
  type t = { name : string; version : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun name version -> ({ name; version } : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "version" Jsont.string ~enc:(fun (v : t) -> v.version)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module ServerInfo = struct
  type t = { name : string; version : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun name version -> ({ name; version } : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "version" Jsont.string ~enc:(fun (v : t) -> v.version)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module Root = struct
  type t = { uri : string; name : string option; meta : Jsont.json option }

  let json : t Jsont.t =
    Jsont.Object.map (fun uri name meta -> ({ uri; name; meta } : t))
    |> Jsont.Object.mem "uri" Jsont.string ~enc:(fun (v : t) -> v.uri)
    |> Jsont.Object.mem "name" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "_meta" (Jsont.option Jsont.json) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.meta)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module SamplingMessage = struct
  type t = { role : string; content : Content.t }

  let json : t Jsont.t =
    Jsont.Object.map (fun role content -> ({ role; content } : t))
    |> Jsont.Object.mem "role" Jsont.string ~enc:(fun (v : t) -> v.role)
    |> Jsont.Object.mem "content" Content.json ~enc:(fun (v : t) -> v.content)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module ModelHint = struct
  type t = { name : string option }

  let json : t Jsont.t =
    Jsont.Object.map (fun name -> ({ name } : t))
    |> Jsont.Object.mem "name" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module ModelPreferences = struct
  type t = {
    hints : ModelHint.t list option;
    cost_priority : float option;
    speed_priority : float option;
    intelligence_priority : float option;
  }

  let json : t Jsont.t =
    Jsont.Object.map
      (fun hints cost_priority speed_priority intelligence_priority ->
        ({ hints; cost_priority; speed_priority; intelligence_priority } : t))
    |> Jsont.Object.mem "hints"
         (Jsont.option (Jsont.list ModelHint.json))
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : t) -> v.hints)
    |> Jsont.Object.mem "costPriority" (Jsont.option Json_codec.number_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.cost_priority)
    |> Jsont.Object.mem "speedPriority" (Jsont.option Json_codec.number_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.speed_priority)
    |> Jsont.Object.mem "intelligencePriority"
         (Jsont.option Json_codec.number_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.intelligence_priority)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module CompletionArgument = struct
  type t = { name : string; value : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun name value -> ({ name; value } : t))
    |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (v : t) -> v.name)
    |> Jsont.Object.mem "value" Jsont.string ~enc:(fun (v : t) -> v.value)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module CompletionReference = struct
  type t = Resource of string | ResourceTemplate of string | Prompt of string

  let json : t Jsont.t =
    Json_codec.map
      ~enc:(function
        | Resource uri | ResourceTemplate uri ->
            Json_codec.object'
              [
                ("type", Jsont.Json.string "ref/resource");
                ("uri", Jsont.Json.string uri);
              ]
        | Prompt name ->
            Json_codec.object'
              [
                ("type", Jsont.Json.string "ref/prompt");
                ("name", Jsont.Json.string name);
              ])
      ~dec:(fun value ->
        match Json_codec.find_member "type" value with
        | Some (Jsont.String ("ref/resource", _)) -> (
            match Json_codec.find_member "uri" value with
            | Some (Jsont.String (uri, _)) -> Ok (Resource uri)
            | _ -> Error "Missing or invalid uri field")
        | Some (Jsont.String ("ref/prompt", _)) -> (
            match Json_codec.find_member "name" value with
            | Some (Jsont.String (name, _)) -> Ok (Prompt name)
            | _ -> Error "Missing or invalid name field")
        | Some (Jsont.String (kind, _)) ->
            Error ("Unknown reference type: " ^ kind)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
end

module Completion = struct
  type t = { values : string list; total : int option; has_more : bool option }

  let json : t Jsont.t =
    Jsont.Object.map (fun values total has_more ->
        ({ values; total; has_more } : t))
    |> Jsont.Object.mem "values" (Jsont.list Jsont.string) ~enc:(fun (v : t) ->
        v.values)
    |> Jsont.Object.mem "total" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.total)
    |> Jsont.Object.mem "hasMore" (Jsont.option Jsont.bool) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.has_more)
    |> Jsont.Object.finish |> Json_codec.last_object
end

module PrimitiveSchema = struct
  type string_schema = {
    type_ : string;
    title : string option;
    description : string option;
    format : string option;
    min_length : int option;
    max_length : int option;
  }

  let string_schema_json : string_schema Jsont.t =
    Jsont.Object.map
      (fun type_ title description format min_length max_length ->
        ({ type_; title; description; format; min_length; max_length }
          : string_schema))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : string_schema) ->
        v.type_)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : string_schema) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : string_schema) -> v.description)
    |> Jsont.Object.mem "format" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : string_schema) -> v.format)
    |> Jsont.Object.mem "minLength" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : string_schema) -> v.min_length)
    |> Jsont.Object.mem "maxLength" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : string_schema) -> v.max_length)
    |> Jsont.Object.finish |> Json_codec.last_object

  type number_schema = {
    type_ : string;
    title : string option;
    description : string option;
    minimum : int option;
    maximum : int option;
  }

  let number_schema_json : number_schema Jsont.t =
    Jsont.Object.map (fun type_ title description minimum maximum ->
        ({ type_; title; description; minimum; maximum } : number_schema))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : number_schema) ->
        v.type_)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : number_schema) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : number_schema) -> v.description)
    |> Jsont.Object.mem "minimum" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : number_schema) -> v.minimum)
    |> Jsont.Object.mem "maximum" (Jsont.option Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : number_schema) -> v.maximum)
    |> Jsont.Object.finish |> Json_codec.last_object

  type boolean_schema = {
    type_ : string;
    title : string option;
    description : string option;
    default : bool option;
  }

  let boolean_schema_json : boolean_schema Jsont.t =
    Jsont.Object.map (fun type_ title description default ->
        ({ type_; title; description; default } : boolean_schema))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : boolean_schema) ->
        v.type_)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : boolean_schema) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : boolean_schema) -> v.description)
    |> Jsont.Object.mem "default" (Jsont.option Jsont.bool) ~dec_absent:None
         ~enc_omit:Option.is_none ~enc:(fun (v : boolean_schema) -> v.default)
    |> Jsont.Object.finish |> Json_codec.last_object

  type enum_schema = {
    type_ : string;
    title : string option;
    description : string option;
    enum : string list;
    enum_names : string list option;
  }

  let enum_schema_json : enum_schema Jsont.t =
    Jsont.Object.map (fun type_ title description enum enum_names ->
        ({ type_; title; description; enum; enum_names } : enum_schema))
    |> Jsont.Object.mem "type" Jsont.string ~enc:(fun (v : enum_schema) ->
        v.type_)
    |> Jsont.Object.mem "title" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : enum_schema) -> v.title)
    |> Jsont.Object.mem "description" (Jsont.option Jsont.string)
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : enum_schema) -> v.description)
    |> Jsont.Object.mem "enum" (Jsont.list Jsont.string)
         ~enc:(fun (v : enum_schema) -> v.enum)
    |> Jsont.Object.mem "enumNames"
         (Jsont.option (Jsont.list Jsont.string))
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : enum_schema) -> v.enum_names)
    |> Jsont.Object.finish |> Json_codec.last_object

  type t =
    | String of string_schema
    | Number of number_schema
    | Boolean of boolean_schema
    | Enum of enum_schema

  let json : t Jsont.t =
    Json_codec.map
      ~enc:(function
        | String value -> Json_codec.encode string_schema_json value
        | Number value -> Json_codec.encode number_schema_json value
        | Boolean value -> Json_codec.encode boolean_schema_json value
        | Enum value -> Json_codec.encode enum_schema_json value)
      ~dec:(fun value ->
        match Json_codec.find_member "type" value with
        | Some (Jsont.String ("string", _)) -> (
            match Json_codec.find_member "enum" value with
            | Some _ ->
                Json_codec.decode enum_schema_json value
                |> Result.map (fun v -> Enum v)
            | None ->
                Json_codec.decode string_schema_json value
                |> Result.map (fun v -> String v))
        | Some (Jsont.String (("integer" | "number"), _)) ->
            Json_codec.decode number_schema_json value
            |> Result.map (fun v -> Number v)
        | Some (Jsont.String ("boolean", _)) ->
            Json_codec.decode boolean_schema_json value
            |> Result.map (fun v -> Boolean v)
        | Some (Jsont.String (kind, _)) -> Error ("Unknown schema type: " ^ kind)
        | Some _ -> Error "type field must be a string"
        | None -> Error "Missing type field")
end

module ElicitationSchema = struct
  type t = {
    type_ : string;
    properties : (string * PrimitiveSchema.t) list;
    required : string list;
  }

  let json : t Jsont.t =
    let object_type =
      Jsont.map Jsont.string ~enc:Fun.id ~dec:(fun kind ->
          if kind = "object" then kind
          else Jsont.Error.msgf Jsont.Meta.none "Expected object schema")
    in
    Jsont.Object.map (fun type_ properties required ->
        { type_; properties; required })
    |> Jsont.Object.mem "type" object_type ~enc:(fun v -> v.type_)
    |> Jsont.Object.mem "properties"
         (Json_codec.assoc_json PrimitiveSchema.json) ~enc:(fun v ->
           v.properties)
    |> Jsont.Object.mem "required" (Jsont.list Jsont.string) ~enc:(fun v ->
        v.required)
    |> Jsont.Object.finish |> Json_codec.first_object
end
