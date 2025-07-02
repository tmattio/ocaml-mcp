open Mcp_sdk
open Eio

type args = { file_path : string; content : string } [@@deriving yojson]

let name = "fs/write"

let description =
  "Write content to a file. For OCaml files (.ml/.mli), automatically formats \
   the code and returns diagnostics."

let handle _sw env merlin_client ocamlformat_client project_root args _ctx =
  let { file_path; content } = args in
  let fs = Stdenv.fs env in

  (* Resolve relative paths against project root *)
  let file_path =
    if Filename.is_relative file_path then
      Filename.concat project_root file_path
    else file_path
  in

  (* Ensure parent directories exist using Eio *)
  let dir = Filename.dirname file_path in
  (try Path.mkdirs ~perm:0o755 Path.(fs / dir)
   with _exn ->
     (* Continue even if mkdirs fails - the actual write will fail with a better error *)
     ());

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
          ~content
      with
      | Ok formatted_content ->
          (formatted_content, Some (Ok "Code formatted successfully"))
      | Error msg ->
          (* If formatting fails, use original content but report the error *)
          (content, Some (Error msg))
    else (content, None)
  in

  (* Write the file using Eio *)
  try
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

          (* Build result *)
          let result_json =
            `Assoc
              [
                ("file_path", `String file_path);
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
              Printf.sprintf "Wrote %s (%s, %d diagnostics)" file_path
                format_status diag_count
            else
              Printf.sprintf "Wrote %s (%s, no diagnostics)" file_path
                format_status
          in

          Ok (Tool_result.structured ~text:text_description result_json)
      | Error err ->
          (* If Merlin fails, still report success but include the error *)
          let result_json =
            `Assoc
              [
                ("file_path", `String file_path);
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
                 (Printf.sprintf "Wrote %s (Merlin error: %s)" file_path err)
               result_json)
    else
      (* For non-OCaml files *)
      Ok
        (Tool_result.text (Printf.sprintf "Successfully wrote to %s" file_path))
  with
  | Sys_error err ->
      Ok (Tool_result.error (Printf.sprintf "Error writing file: %s" err))
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
                          ( "description",
                            `String "The path to the file to write" );
                        ] );
                    ( "content",
                      `Assoc
                        [
                          ("type", `String "string");
                          ( "description",
                            `String "The content to write to the file" );
                        ] );
                  ] );
              ("required", `List [ `String "file_path"; `String "content" ]);
            ]
      end)
    (handle sw env merlin_client ocamlformat_client project_root)
