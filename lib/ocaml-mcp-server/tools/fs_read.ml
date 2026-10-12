open Ocaml_platform_sdk

let name = "fs_read"

let description =
  "Read the content of any file. When reading OCaml files (.ml/.mli), the \
   result includes Merlin diagnostics."

module Args = struct
  type t = { file_path : string; offset : int option; limit : int option }

  let json : t Jsont.t =
    Jsont.Object.map (fun file_path offset limit ->
        ({ file_path; offset; limit } : t))
    |> Jsont.Object.mem "file_path" Jsont.string ~enc:(fun (v : t) ->
        v.file_path)
    |> Jsont.Object.mem "offset"
         (Jsont.option Mcp.Types.Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.offset)
    |> Jsont.Object.mem "limit" (Jsont.option Mcp.Types.Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) -> v.limit)
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
                      Mcp.Json.string "The path to the file to read" );
                  ] );
              ( "offset",
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "integer");
                    ( "description",
                      Mcp.Json.string
                        "Optional: The 1-based line number to start reading \
                         from" );
                  ] );
              ( "limit",
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "integer");
                    ( "description",
                      Mcp.Json.string
                        "Optional: Maximum number of lines to read" );
                  ] );
            ] );
        ("required", Mcp.Json.array [ Mcp.Json.string "file_path" ]);
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
    content : string;
    diagnostics : diagnostic list option;
    merlin_error : string option;
  }

  let json : t Jsont.t =
    Jsont.Object.map (fun content diagnostics merlin_error ->
        ({ content; diagnostics; merlin_error } : t))
    |> Jsont.Object.mem "content" Jsont.string ~enc:(fun (v : t) -> v.content)
    |> Jsont.Object.mem "diagnostics"
         (Jsont.option (Jsont.list diagnostic_json))
         ~enc:(fun (v : t) -> v.diagnostics)
    |> Jsont.Object.mem "merlin_error" (Jsont.option Jsont.string)
         ~enc:(fun (v : t) -> v.merlin_error)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
end

module Error = struct
  type t =
    | File_not_found of string
    | Permission_denied of string
    | IO_error of string

  let to_string = function
    | File_not_found path -> Printf.sprintf "File not found: %s" path
    | Permission_denied path -> Printf.sprintf "Permission denied: %s" path
    | IO_error msg -> Printf.sprintf "I/O error: %s" msg
end

let apply_line_filter content offset limit =
  match (offset, limit) with
  | None, None -> content
  | _ ->
      let lines = String.split_on_char '\n' content in
      let selected_lines =
        let rec select_lines lines line_num acc =
          match lines with
          | [] -> List.rev acc
          | line :: rest ->
              let should_include =
                match (offset, limit) with
                | Some o, Some l when line_num >= o && line_num < o + l -> true
                | Some o, None when line_num >= o -> true
                | None, Some l when line_num <= l -> true
                | None, None -> true
                | _ -> false
              in
              if should_include then
                select_lines rest (line_num + 1) (line :: acc)
              else select_lines rest (line_num + 1) acc
        in
        select_lines lines 1 []
      in
      String.concat "\n" selected_lines

let execute ~sw:_ ~env (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let { Args.file_path; offset; limit } = args in
  let fs = Eio.Stdenv.fs env in

  (* Check if file exists and read it *)
  try
    let full_content = Eio.Path.load Eio.Path.(fs / file_path) in

    (* Apply offset and limit if specified *)
    let content = apply_line_filter full_content offset limit in

    (* Check if it's an OCaml file *)
    let is_ocaml_file =
      Filename.check_suffix file_path ".ml"
      || Filename.check_suffix file_path ".mli"
    in

    if is_ocaml_file then
      (* Get diagnostics from Merlin *)
      match
        Merlin.diagnostics sdk ~source_path:file_path ~source_text:content
      with
      | Ok diagnostics ->
          (* Format diagnostics *)
          let formatted_diagnostics =
            List.map
              (fun report ->
                let module Loc = Ocaml_parsing.Location in
                let loc = Loc.loc_of_report report in
                let message = Format.asprintf "%a" Loc.print_main report in
                let severity =
                  match report.source with Warning -> "warning" | _ -> "error"
                in
                {
                  Output.message;
                  severity;
                  start_line = loc.loc_start.pos_lnum;
                  start_col = loc.loc_start.pos_cnum - loc.loc_start.pos_bol;
                  end_line = loc.loc_end.pos_lnum;
                  end_col = loc.loc_end.pos_cnum - loc.loc_end.pos_bol;
                })
              diagnostics
          in
          Ok
            {
              Output.content;
              diagnostics = Some formatted_diagnostics;
              merlin_error = None;
            }
      | Error err ->
          (* If Merlin fails, still return the content *)
          Ok { Output.content; diagnostics = None; merlin_error = Some err }
    else
      (* For non-OCaml files, just return the content *)
      Ok { Output.content; diagnostics = None; merlin_error = None }
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found file_path)
  | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) ->
      Error (Error.Permission_denied file_path)
  | exn -> Error (Error.IO_error (Printexc.to_string exn))
