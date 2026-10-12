open Ocaml_platform_sdk

let name = "ocaml_find_references"
let description = "Find all usages of a symbol"

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
  type reference = {
    file : string;
    start_line : int;
    start_col : int;
    end_line : int;
    end_col : int;
  }

  let reference_json : reference Jsont.t =
    Jsont.Object.map (fun file start_line start_col end_line end_col ->
        ({ file; start_line; start_col; end_line; end_col } : reference))
    |> Jsont.Object.mem "file" Jsont.string ~enc:(fun (v : reference) -> v.file)
    |> Jsont.Object.mem "start_line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : reference) -> v.start_line)
    |> Jsont.Object.mem "start_col" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : reference) -> v.start_col)
    |> Jsont.Object.mem "end_line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : reference) -> v.end_line)
    |> Jsont.Object.mem "end_col" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : reference) -> v.end_col)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  type t = { references : reference list; count : int }

  let json : t Jsont.t =
    Jsont.Object.map (fun references count -> ({ references; count } : t))
    |> Jsont.Object.mem "references" (Jsont.list reference_json)
         ~enc:(fun (v : t) -> v.references)
    |> Jsont.Object.mem "count" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : t) -> v.count)
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
      Merlin.find_references sdk ~source_path:args.Args.file_path ~source_text
        ~line:args.Args.line ~col:args.Args.column
    with
    | Ok locs ->
        let references =
          List.map
            (fun (loc, fname) ->
              {
                Output.file = fname;
                start_line = loc.Ocaml_utils.Warnings.loc_start.pos_lnum;
                start_col = loc.loc_start.pos_cnum - loc.loc_start.pos_bol;
                end_line = loc.loc_end.pos_lnum;
                end_col = loc.loc_end.pos_cnum - loc.loc_end.pos_bol;
              })
            locs
        in
        Ok { Output.references; count = List.length references }
    | Error err -> Error (Error.Merlin_error err)
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found args.Args.file_path)
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      Error (Error.Read_error (Printexc.to_string exn))
  | exn -> Error (Error.Read_error (Printexc.to_string exn))
