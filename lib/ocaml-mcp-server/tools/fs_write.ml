open Ocaml_platform_sdk

let name = "fs_write"

let description =
  "Write content to a file. For OCaml files (.ml/.mli), automatically formats \
   the code and returns diagnostics."

module Args = struct
  type t = { file_path : string; content : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun file_path content -> ({ file_path; content } : t))
    |> Jsont.Object.mem "file_path" Jsont.string ~enc:(fun (v : t) ->
        v.file_path)
    |> Jsont.Object.mem "content" Jsont.string ~enc:(fun (v : t) -> v.content)
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
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "string");
                    ( "description",
                      Mcp.Json.string "The path to the file to write" );
                  ] );
              ( "content",
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "string");
                    ( "description",
                      Mcp.Json.string "The content to write to the file" );
                  ] );
            ] );
        ( "required",
          Mcp.Json.array
            [ Mcp.Json.string "file_path"; Mcp.Json.string "content" ] );
      ]
end

module Output = struct
  type diagnostic = {
    message : string;
    severity : string;
    start_line : int;
    start_col : int;
    end_line : int;
    end_col : int;
  }

  let diagnostic_json : diagnostic Jsont.t =
    Jsont.Object.map
      (fun message severity start_line start_col end_line end_col ->
        ({ message; severity; start_line; start_col; end_line; end_col }
          : diagnostic))
    |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (v : diagnostic) ->
        v.message)
    |> Jsont.Object.mem "severity" Jsont.string ~enc:(fun (v : diagnostic) ->
        v.severity)
    |> Jsont.Object.mem "start_line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.start_line)
    |> Jsont.Object.mem "start_col" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.start_col)
    |> Jsont.Object.mem "end_line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.end_line)
    |> Jsont.Object.mem "end_col" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.end_col)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  type t = {
    path : string;
    formatted : bool;
    diagnostics : diagnostic list option;
  }

  let json : t Jsont.t =
    Jsont.Object.map (fun path formatted diagnostics ->
        ({ path; formatted; diagnostics } : t))
    |> Jsont.Object.mem "path" Jsont.string ~enc:(fun (v : t) -> v.path)
    |> Jsont.Object.mem "formatted" Jsont.bool ~enc:(fun (v : t) -> v.formatted)
    |> Jsont.Object.mem "diagnostics"
         (Jsont.option (Jsont.list diagnostic_json))
         ~enc:(fun (v : t) -> v.diagnostics)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
end

module Error = struct
  type t = Permission_denied of string | IO_error of string

  let to_string = function
    | Permission_denied path -> Printf.sprintf "Permission denied: %s" path
    | IO_error msg -> Printf.sprintf "I/O error: %s" msg
end

let execute ~sw:_ ~env (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let { Args.file_path; content } = args in
  let fs = Eio.Stdenv.fs env in

  (* Ensure parent directories exist using Eio *)
  let dir = Filename.dirname file_path in
  (try Eio.Path.mkdirs ~perm:0o755 Eio.Path.(fs / dir)
   with _exn ->
     (* Directory might already exist or we're in a normal case where parent exists *)
     ());

  (* Check if it's an OCaml file *)
  let is_ocaml_file =
    Filename.check_suffix file_path ".ml"
    || Filename.check_suffix file_path ".mli"
  in

  let final_content, formatted, diagnostics =
    if is_ocaml_file then
      (* Format with ocamlformat *)
      match Ocamlformat.format_doc sdk ~path:file_path ~content with
      | Ok formatted_content ->
          (* Get diagnostics from Merlin *)
          let diagnostics =
            match
              Merlin.diagnostics sdk ~source_path:file_path
                ~source_text:formatted_content
            with
            | Ok reports ->
                Some
                  (List.map
                     (fun report ->
                       let module Loc = Ocaml_parsing.Location in
                       let loc = Loc.loc_of_report report in
                       let message =
                         Format.asprintf "%a" Loc.print_main report
                       in
                       let severity =
                         match report.source with
                         | Warning -> "warning"
                         | _ -> "error"
                       in
                       {
                         Output.message;
                         severity;
                         start_line = loc.loc_start.pos_lnum;
                         start_col =
                           loc.loc_start.pos_cnum - loc.loc_start.pos_bol;
                         end_line = loc.loc_end.pos_lnum;
                         end_col = loc.loc_end.pos_cnum - loc.loc_end.pos_bol;
                       })
                     reports)
            | Error _ -> None
          in
          (formatted_content, true, diagnostics)
      | Error _ -> (content, false, None)
    else (content, false, None)
  in

  (* Write the file *)
  try
    Eio.Path.save
      Eio.Path.(fs / file_path)
      final_content ~create:(`Or_truncate 0o644);
    Ok { Output.path = file_path; formatted; diagnostics }
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) ->
      Error (Error.Permission_denied file_path)
  | exn -> Error (Error.IO_error (Printexc.to_string exn))
