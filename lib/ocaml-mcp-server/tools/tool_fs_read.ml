open Mcp_sdk

type args = {
  file_path : string;
  offset : int option; [@default None]
  limit : int option; [@default None]
} [@@deriving yojson]

let name = "fs/read"
let description = "Read the content of any file. When reading OCaml files (.ml/.mli), the result includes Merlin diagnostics."

let read_file_lines file_path offset limit =
  let ic = open_in file_path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let lines = ref [] in
    let line_num = ref 1 in
    try
      while true do
        let line = input_line ic in
        match offset, limit with
        | Some o, Some l when !line_num >= o && !line_num < o + l ->
            lines := line :: !lines
        | Some o, None when !line_num >= o ->
            lines := line :: !lines
        | None, Some l when !line_num <= l ->
            lines := line :: !lines
        | None, None ->
            lines := line :: !lines
        | _ -> ()
        ;
        incr line_num
      done;
      assert false
    with End_of_file ->
      List.rev !lines
  )

let handle merlin_client args _ctx =
  let { file_path; offset; limit } = args in
  
  (* Check if file exists *)
  if not (Sys.file_exists file_path) then
    Ok (Tool_result.error (Printf.sprintf "File not found: %s" file_path))
  else if Sys.is_directory file_path then
    Ok (Tool_result.error (Printf.sprintf "Path is a directory, not a file: %s" file_path))
  else
    try
      (* Read file content *)
      let lines = read_file_lines file_path offset limit in
      let content = String.concat "\n" lines in
      
      (* Check if it's an OCaml file *)
      let is_ocaml_file = 
        Filename.check_suffix file_path ".ml" || 
        Filename.check_suffix file_path ".mli" 
      in
      
      if is_ocaml_file then
        (* Get diagnostics from Merlin *)
        match Merlin_client.diagnostics merlin_client ~source_path:file_path ~source_text:content with
        | Ok diagnostics ->
            (* Format diagnostics *)
            let diagnostics_json = 
              `List (List.map (fun report ->
                let module Loc = Ocaml_parsing.Location in
                let loc = Loc.loc_of_report report in
                let message = Format.asprintf "%a" Loc.print_main report in
                let severity = match report.source with
                  | Warning -> "warning"
                  | _ -> "error"
                in
                `Assoc [
                  ("message", `String message);
                  ("severity", `String severity);
                  ("start", `Assoc [
                    ("line", `Int loc.loc_start.pos_lnum);
                    ("col", `Int (loc.loc_start.pos_cnum - loc.loc_start.pos_bol))
                  ]);
                  ("end", `Assoc [
                    ("line", `Int loc.loc_end.pos_lnum);
                    ("col", `Int (loc.loc_end.pos_cnum - loc.loc_end.pos_bol))
                  ])
                ]
              ) diagnostics)
            in
            
            (* Return structured result *)
            let result_json = `Assoc [
              ("content", `String content);
              ("diagnostics", diagnostics_json)
            ] in
            
            let text_description = 
              if List.length diagnostics > 0 then
                Printf.sprintf "Read %s (%d diagnostics found)" file_path (List.length diagnostics)
              else
                Printf.sprintf "Read %s (no diagnostics)" file_path
            in
            
            Ok (Tool_result.structured ~text:text_description result_json)
            
        | Error err ->
            (* If Merlin fails, still return the content *)
            let result_json = `Assoc [
              ("content", `String content);
              ("diagnostics", `List []);
              ("merlin_error", `String err)
            ] in
            Ok (Tool_result.structured ~text:(Printf.sprintf "Read %s (Merlin error: %s)" file_path err) result_json)
      else
        (* For non-OCaml files, just return the content *)
        Ok (Tool_result.text content)
        
    with
    | Sys_error err -> Ok (Tool_result.error (Printf.sprintf "Error reading file: %s" err))
    | exn -> Ok (Tool_result.error (Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)))

let register server ~merlin_client =
  Server.tool server name ~description
    ~args:(module struct
      type t = args
      let to_yojson = args_to_yojson
      let of_yojson = args_of_yojson
      let schema () = 
        `Assoc [
          ("type", `String "object");
          ("properties", `Assoc [
            ("file_path", `Assoc [
              ("type", `String "string");
              ("description", `String "The path to the file to read")
            ]);
            ("offset", `Assoc [
              ("type", `String "integer");
              ("description", `String "Optional: The 1-based line number to start reading from")
            ]);
            ("limit", `Assoc [
              ("type", `String "integer");
              ("description", `String "Optional: Maximum number of lines to read")
            ])
          ]);
          ("required", `List [`String "file_path"])
        ]
    end)
    (handle merlin_client)