open Eio

module Args = struct
  type t = {
    file_path : string;
    offset : int option; [@default None]
    limit : int option; [@default None]
  }
  [@@deriving yojson]

  let schema () =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "file_path",
                `Assoc
                  [
                    ("type", `String "string");
                    ("description", `String "The path to the file to read");
                  ] );
              ( "offset",
                `Assoc
                  [
                    ("type", `String "integer");
                    ( "description",
                      `String
                        "Optional: The 1-based line number to start reading \
                         from" );
                  ] );
              ( "limit",
                `Assoc
                  [
                    ("type", `String "integer");
                    ( "description",
                      `String "Optional: Maximum number of lines to read" );
                  ] );
            ] );
        ("required", `List [ `String "file_path" ]);
      ]
end

let name = "fs_read"

let description =
  "Read the content of any file. When reading OCaml files (.ml/.mli), the \
   result includes Merlin diagnostics."

let execute context args =
  let { Args.file_path; offset; limit } = args in

  (* Resolve relative paths against project root *)
  let file_path =
    if Filename.is_relative file_path then
      Filename.concat context.Context.project_root file_path
    else file_path
  in

  let fs = Stdenv.fs context.Context.env in

  (* Check if file exists and read it *)
  try
    let full_content = Path.load Path.(fs / file_path) in

    (* Apply offset and limit if specified *)
    let content =
      match (offset, limit) with
      | None, None -> full_content
      | _ ->
          let lines = String.split_on_char '\n' full_content in
          let selected_lines =
            let rec select_lines lines line_num acc =
              match lines with
              | [] -> List.rev acc
              | line :: rest ->
                  let should_include =
                    match (offset, limit) with
                    | Some o, Some l when line_num >= o && line_num < o + l ->
                        true
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
    in

    (* Check if it's an OCaml file *)
    let is_ocaml_file =
      Filename.check_suffix file_path ".ml"
      || Filename.check_suffix file_path ".mli"
    in

    if is_ocaml_file then
      (* Get diagnostics from Merlin *)
      match
        Merlin_client.diagnostics context.Context.merlin ~source_path:file_path
          ~source_text:content
      with
      | Ok diagnostics ->
          (* Format diagnostics *)
          let diagnostics_json =
            `List
              (List.map
                 (fun report ->
                   let module Loc = Ocaml_parsing.Location in
                   let loc = Loc.loc_of_report report in
                   let message = Format.asprintf "%a" Loc.print_main report in
                   let severity =
                     match report.source with
                     | Warning -> "warning"
                     | _ -> "error"
                   in
                   `Assoc
                     [
                       ("message", `String message);
                       ("severity", `String severity);
                       ( "start",
                         `Assoc
                           [
                             ("line", `Int loc.loc_start.pos_lnum);
                             ( "col",
                               `Int
                                 (loc.loc_start.pos_cnum - loc.loc_start.pos_bol)
                             );
                           ] );
                       ( "end",
                         `Assoc
                           [
                             ("line", `Int loc.loc_end.pos_lnum);
                             ( "col",
                               `Int (loc.loc_end.pos_cnum - loc.loc_end.pos_bol)
                             );
                           ] );
                     ])
                 diagnostics)
          in

          (* Return structured result *)
          let result_json =
            `Assoc
              [
                ("content", `String content); ("diagnostics", diagnostics_json);
              ]
          in

          let text_description =
            if List.length diagnostics > 0 then
              Printf.sprintf "Read %s (%d diagnostics found)" file_path
                (List.length diagnostics)
            else Printf.sprintf "Read %s (no diagnostics)" file_path
          in

          Ok (Mcp_sdk.Tool_result.structured ~text:text_description result_json)
      | Error err ->
          (* If Merlin fails, still return the content *)
          let result_json =
            `Assoc
              [
                ("content", `String content);
                ("diagnostics", `List []);
                ("merlin_error", `String err);
              ]
          in
          Ok
            (Mcp_sdk.Tool_result.structured
               ~text:(Printf.sprintf "Read %s (Merlin error: %s)" file_path err)
               result_json)
    else
      (* For non-OCaml files, just return the content *)
      Ok (Mcp_sdk.Tool_result.text content)
  with
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      let msg =
        match exn with
        | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
            Printf.sprintf "File not found: %s" file_path
        | Eio.Io (Eio.Fs.E _, _) ->
            Printf.sprintf "I/O error: %s" (Printexc.to_string exn)
        | _ -> Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)
      in
      Ok (Mcp_sdk.Tool_result.error msg)
  | exn ->
      Ok
        (Mcp_sdk.Tool_result.error
           (Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)))

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
