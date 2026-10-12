open Ocaml_platform_sdk

let name = "ocaml_find_definition"
let description = "Find where a symbol is defined"

module Args = struct
  type t = { file_path : string; line : int; column : int }

  let json : t Jsont.t =
    Jsont.Object.map (fun file_path line column ->
        ({ file_path; line; column } : t))
    |> Jsont.Object.mem "file_path" Jsont.string ~enc:(fun (v : t) ->
        v.file_path)
    |> Jsont.Object.mem "line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : t) -> v.line)
    |> Jsont.Object.mem "column" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : t) -> v.column)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  let schema () =
    Mcp.Json.object_
      [
        ("type", Mcp.Json.string "object");
        ( "properties",
          Mcp.Json.object_
            [
              ( "file_path",
                Mcp.Json.object_ [ ("type", Mcp.Json.string "string") ] );
              ("line", Mcp.Json.object_ [ ("type", Mcp.Json.string "integer") ]);
              ( "column",
                Mcp.Json.object_ [ ("type", Mcp.Json.string "integer") ] );
            ] );
        ( "required",
          Mcp.Json.array
            [
              Mcp.Json.string "file_path";
              Mcp.Json.string "line";
              Mcp.Json.string "column";
            ] );
      ]
end

module Output = struct
  type location = { path : string; line : int; column : int }

  let location_json : location Jsont.t =
    Jsont.Object.map (fun path line column ->
        ({ path; line; column } : location))
    |> Jsont.Object.mem "path" Jsont.string ~enc:(fun (v : location) -> v.path)
    |> Jsont.Object.mem "line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : location) -> v.line)
    |> Jsont.Object.mem "column" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : location) -> v.column)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  type t = { definition : location option; message : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun definition message -> ({ definition; message } : t))
    |> Jsont.Object.mem "definition" (Jsont.option location_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.definition)
    |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (v : t) -> v.message)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
end

module Error = struct
  type t =
    | File_not_found of string
    | Read_error of string
    | Merlin_error of string

  let to_string = function
    | File_not_found path -> Printf.sprintf "File not found: %s" path
    | Read_error msg -> Printf.sprintf "Failed to read file: %s" msg
    | Merlin_error msg -> Printf.sprintf "Merlin error: %s" msg
end

let execute ~sw:_ ~env (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  try
    let fs = Eio.Stdenv.fs env in
    let source_text = Eio.Path.load Eio.Path.(fs / args.Args.file_path) in
    match
      Merlin.find_definition sdk ~source_path:args.Args.file_path ~source_text
        ~line:args.Args.line ~col:args.Args.column
    with
    | Ok (path, pos) ->
        let location =
          {
            Output.path;
            line = pos.pos_lnum;
            column = pos.pos_cnum - pos.pos_bol;
          }
        in
        Ok
          {
            Output.definition = Some location;
            message =
              Printf.sprintf "Definition found at: %s:%d:%d" path pos.pos_lnum
                (pos.pos_cnum - pos.pos_bol);
          }
    | Error err -> Error (Error.Merlin_error err)
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found args.Args.file_path)
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      Error (Error.Read_error (Printexc.to_string exn))
  | exn -> Error (Error.Read_error (Printexc.to_string exn))
