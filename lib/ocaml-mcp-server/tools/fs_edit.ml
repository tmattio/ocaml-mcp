open Ocaml_platform_sdk

let name = "fs_edit"

let description =
  "Replace text within a file. For OCaml files (.ml/.mli), automatically \
   formats the result and returns diagnostics."

module Args = struct
  type t = {
    file_path : string;
    old_string : string;
    new_string : string;
    expected_replacements : int option; [@default None]
    replace_all : bool option; [@default None]
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
                      `String "Number of replacements expected (defaults to 1)"
                    );
                  ] );
              ( "replace_all",
                `Assoc
                  [
                    ("type", `String "boolean");
                    ( "description",
                      `String
                        "Replace all occurrences of the string (overrides \
                         expected_replacements)" );
                  ] );
            ] );
        ( "required",
          `List
            [ `String "file_path"; `String "old_string"; `String "new_string" ]
        );
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
  [@@deriving yojson]

  type t = {
    replacements_made : int;
    diagnostics : diagnostic list option; [@yojson.option]
    formatted : bool;
  }
  [@@deriving yojson]
end

module Error = struct
  type t =
    | File_not_found of string
    | Permission_denied of string
    | IO_error of string
    | Replacement_count_mismatch of { expected : int; actual : int }
    | String_not_found

  let to_string = function
    | File_not_found path -> Printf.sprintf "File not found: %s" path
    | Permission_denied path -> Printf.sprintf "Permission denied: %s" path
    | IO_error msg -> Printf.sprintf "I/O error: %s" msg
    | Replacement_count_mismatch { expected; actual } ->
        Printf.sprintf "Expected %d replacements but found %d" expected actual
    | String_not_found -> "The specified string was not found in the file"
end

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

let execute ~sw:_ ~env (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let {
    Args.file_path;
    old_string;
    new_string;
    expected_replacements;
    replace_all;
  } =
    args
  in
  let fs = Eio.Stdenv.fs env in

  try
    (* Read current file content *)
    let content = Eio.Path.load Eio.Path.(fs / file_path) in

    (* Count occurrences *)
    let occurrences = count_occurrences content old_string in

    (* Determine expected replacement count *)
    let expected_count =
      match (replace_all, expected_replacements) with
      | Some true, _ -> occurrences
      | _, Some n -> n
      | _ -> 1
    in

    (* Check if we have the expected occurrences *)
    if occurrences = 0 then Error Error.String_not_found
    else if occurrences < expected_count then
      Error
        (Error.Replacement_count_mismatch
           { expected = expected_count; actual = occurrences })
    else
      (* Perform replacements *)
      let new_content =
        if Option.value ~default:false replace_all then
          replace_all_occurrences content old_string new_string
        else
          (* Replace only the expected number of occurrences *)
          let rec replace_n text n =
            if n = 0 then text
            else
              match String.index_opt text old_string.[0] with
              | None -> text
              | Some idx ->
                  if idx + String.length old_string <= String.length text then
                    let substr =
                      String.sub text idx (String.length old_string)
                    in
                    if substr = old_string then
                      let before = String.sub text 0 idx in
                      let after =
                        String.sub text
                          (idx + String.length old_string)
                          (String.length text - idx - String.length old_string)
                      in
                      before ^ new_string ^ replace_n after (n - 1)
                    else
                      let before = String.sub text 0 (idx + 1) in
                      let after =
                        String.sub text (idx + 1) (String.length text - idx - 1)
                      in
                      before ^ replace_n after n
                  else text
          in
          replace_n content expected_count
      in

      (* Check if it's an OCaml file *)
      let is_ocaml_file =
        Filename.check_suffix file_path ".ml"
        || Filename.check_suffix file_path ".mli"
      in

      let final_content, formatted, diagnostics =
        if is_ocaml_file then
          (* Format with ocamlformat *)
          match
            Ocamlformat.format_doc sdk ~path:file_path ~content:new_content
          with
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
                             end_col =
                               loc.loc_end.pos_cnum - loc.loc_end.pos_bol;
                           })
                         reports)
                | Error _ -> None
              in
              (formatted_content, true, diagnostics)
          | Error _ -> (new_content, false, None)
        else (new_content, false, None)
      in

      (* Write the file *)
      Eio.Path.save Eio.Path.(fs / file_path) final_content ~create:`Never;

      Ok { Output.replacements_made = expected_count; diagnostics; formatted }
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found file_path)
  | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) ->
      Error (Error.Permission_denied file_path)
  | exn -> Error (Error.IO_error (Printexc.to_string exn))
