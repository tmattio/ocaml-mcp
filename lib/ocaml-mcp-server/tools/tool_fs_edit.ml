open Mcp_sdk
open Eio

type args = {
  file_path : string;
  old_string : string;
  new_string : string;
  expected_replacements : int option; [@default None]
  replace_all : bool option; [@default None]
}
[@@deriving yojson]

let name = "fs_edit"

let description =
  "Replace text within a file. For OCaml files (.ml/.mli), automatically \
   formats the result and returns diagnostics."

let count_occurrences text pattern =
  let rec count pos acc =
    try
      let idx = String.index_from text pos pattern.[0] in
      if idx + String.length pattern <= String.length text then
        let substr = String.sub text idx (String.length pattern) in
        if substr = pattern then count (idx + 1) (acc + 1)
        else count (idx + 1) acc
      else acc
    with Not_found -> acc
  in
  count 0 0

let replace_all_occurrences text old_string new_string =
  let rec replace acc pos =
    try
      let idx = String.index_from text pos old_string.[0] in
      if idx + String.length old_string <= String.length text then
        let substr = String.sub text idx (String.length old_string) in
        if substr = old_string then
          let before = String.sub text pos (idx - pos) in
          replace (acc ^ before ^ new_string) (idx + String.length old_string)
        else replace acc (idx + 1)
      else acc ^ String.sub text pos (String.length text - pos)
    with Not_found -> acc ^ String.sub text pos (String.length text - pos)
  in
  replace "" 0

let handle _sw env merlin_client ocamlformat_client project_root args _ctx =
  let { file_path; old_string; new_string; expected_replacements; replace_all }
      =
    args
  in

  (* Resolve relative paths against project root *)
  let file_path =
    if Filename.is_relative file_path then
      Filename.concat project_root file_path
    else file_path
  in

  let fs = Stdenv.fs env in

  try
    (* Read current file content *)
    let content = Path.load Path.(fs / file_path) in

    (* Count occurrences *)
    let occurrences = count_occurrences content old_string in

    (* Check expected replacements *)
    let check_expected =
      match (replace_all, expected_replacements) with
      | Some true, _ ->
          true (* replace_all=true means replace all occurrences *)
      | _, Some expected -> occurrences = expected
      | _, None -> occurrences = 1 (* default: expect exactly 1 replacement *)
    in

    if occurrences = 0 then
      Ok
        (Tool_result.error
           (Printf.sprintf
              "Failed to edit: could not find the string to replace in %s"
              file_path))
    else if (not check_expected) && replace_all <> Some true then
      let expected = Option.value expected_replacements ~default:1 in
      Ok
        (Tool_result.error
           (Printf.sprintf
              "Failed to edit: expected %d replacements but found %d in %s"
              expected occurrences file_path))
    else
      (* Perform replacement *)
      let new_content = replace_all_occurrences content old_string new_string in

      (* Check if it's an OCaml file *)
      let is_ocaml_file =
        Filename.check_suffix file_path ".ml"
        || Filename.check_suffix file_path ".mli"
      in

      let final_content, format_result =
        if is_ocaml_file then
          (* Try to format with ocamlformat *)
          match
            Ocamlformat_client.format_doc ocamlformat_client ~path:file_path
              ~content:new_content
          with
          | Ok formatted_content ->
              (formatted_content, Some (Ok "Code formatted successfully"))
          | Error msg ->
              (* If formatting fails, use original content but report the error *)
              (new_content, Some (Error msg))
        else (new_content, None)
      in

      (* Write the file using Eio *)
      Path.save ~create:(`Or_truncate 0o644) Path.(fs / file_path) final_content;

      if is_ocaml_file then
        (* Get diagnostics from Merlin after writing *)
        match
          Merlin_client.diagnostics merlin_client ~source_path:file_path
            ~source_text:final_content
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
                                   (loc.loc_start.pos_cnum
                                  - loc.loc_start.pos_bol) );
                             ] );
                         ( "end",
                           `Assoc
                             [
                               ("line", `Int loc.loc_end.pos_lnum);
                               ( "col",
                                 `Int
                                   (loc.loc_end.pos_cnum - loc.loc_end.pos_bol)
                               );
                             ] );
                       ])
                   diagnostics)
            in

            (* Build result *)
            let result_json =
              `Assoc
                [
                  ("file_path", `String file_path);
                  ("replacements", `Int occurrences);
                  ("diagnostics", diagnostics_json);
                  ( "format_result",
                    match format_result with
                    | Some (Ok msg) -> `String msg
                    | Some (Error err) -> `Assoc [ ("error", `String err) ]
                    | None -> `Null );
                ]
            in

            let text_description =
              let diag_count = List.length diagnostics in
              let format_status =
                match format_result with
                | Some (Ok _) -> "formatted"
                | Some (Error _) -> "format failed"
                | None -> ""
              in
              if diag_count > 0 then
                Printf.sprintf "Edited %s (%d replacements, %s, %d diagnostics)"
                  file_path occurrences format_status diag_count
              else
                Printf.sprintf "Edited %s (%d replacements, %s, no diagnostics)"
                  file_path occurrences format_status
            in

            Ok (Tool_result.structured ~text:text_description result_json)
        | Error err ->
            (* If Merlin fails, still report success but include the error *)
            let result_json =
              `Assoc
                [
                  ("file_path", `String file_path);
                  ("replacements", `Int occurrences);
                  ("diagnostics", `List []);
                  ("merlin_error", `String err);
                  ( "format_result",
                    match format_result with
                    | Some (Ok msg) -> `String msg
                    | Some (Error err) -> `Assoc [ ("error", `String err) ]
                    | None -> `Null );
                ]
            in
            Ok
              (Tool_result.structured
                 ~text:
                   (Printf.sprintf
                      "Edited %s (%d replacements, Merlin error: %s)" file_path
                      occurrences err)
                 result_json)
      else
        (* For non-OCaml files *)
        Ok
          (Tool_result.text
             (Printf.sprintf "Successfully modified %s (%d replacements)"
                file_path occurrences))
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
      Ok (Tool_result.error msg)
  | exn ->
      Ok
        (Tool_result.error
           (Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)))

let register server ~sw ~env ~merlin_client ~ocamlformat_client ~project_root =
  Server.tool server name ~description
    ~args:
      (module struct
        type t = args

        let to_yojson = args_to_yojson
        let of_yojson = args_of_yojson

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
                          ("description", `String "The path to the file to edit");
                        ] );
                    ( "old_string",
                      `Assoc
                        [
                          ("type", `String "string");
                          ("description", `String "The exact text to replace");
                        ] );
                    ( "new_string",
                      `Assoc
                        [
                          ("type", `String "string");
                          ("description", `String "The text to replace it with");
                        ] );
                    ( "expected_replacements",
                      `Assoc
                        [
                          ("type", `String "integer");
                          ( "description",
                            `String
                              "Number of replacements expected (defaults to 1)"
                          );
                        ] );
                    ( "replace_all",
                      `Assoc
                        [
                          ("type", `String "boolean");
                          ( "description",
                            `String
                              "Replace all occurrences of the string \
                               (overrides expected_replacements)" );
                        ] );
                  ] );
              ( "required",
                `List
                  [
                    `String "file_path";
                    `String "old_string";
                    `String "new_string";
                  ] );
            ]
      end)
    (handle sw env merlin_client ocamlformat_client project_root)
