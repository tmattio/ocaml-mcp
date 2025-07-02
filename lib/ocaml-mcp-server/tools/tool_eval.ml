(** OCaml REPL evaluation tool *)

open Mcp_sdk

type args = { code : string } [@@deriving yojson]

let name = "ocaml/eval"
let description = "Evaluate OCaml expressions in project context"

(* Capture stdout/stderr during evaluation *)
let capture_output f =
  let old_stdout = Unix.dup Unix.stdout in
  let old_stderr = Unix.dup Unix.stderr in
  let r_out, w_out = Unix.pipe () in
  let r_err, w_err = Unix.pipe () in
  Unix.dup2 w_out Unix.stdout;
  Unix.dup2 w_err Unix.stderr;
  let result = 
    try 
      let res = f () in
      Unix.close w_out;
      Unix.close w_err;
      let out_buf = Buffer.create 1024 in
      let err_buf = Buffer.create 1024 in
      let tmp = Bytes.create 1024 in
      let rec read_all fd buf =
        match Unix.read fd tmp 0 1024 with
        | 0 -> ()
        | n -> Buffer.add_subbytes buf tmp 0 n; read_all fd buf
      in
      read_all r_out out_buf;
      read_all r_err err_buf;
      Unix.close r_out;
      Unix.close r_err;
      Ok (res, Buffer.contents out_buf, Buffer.contents err_buf)
    with e ->
      Unix.close w_out;
      Unix.close w_err;
      Unix.close r_out;
      Unix.close r_err;
      Error e
  in
  Unix.dup2 old_stdout Unix.stdout;
  Unix.dup2 old_stderr Unix.stderr;
  Unix.close old_stdout;
  Unix.close old_stderr;
  result

let run_toplevel_phrase code =
  (* Ensure code ends with ;; for proper parsing *)
  let code = 
    let trimmed = String.trim code in
    if String.length trimmed >= 2 && 
       String.sub trimmed (String.length trimmed - 2) 2 = ";;" then
      trimmed
    else
      trimmed ^ ";;" 
  in
  
  let lexbuf = Lexing.from_string code in
  try
    let phrase = !Toploop.parse_toplevel_phrase lexbuf in
    capture_output (fun () -> 
      let fmt = Format.str_formatter in
      let result = Toploop.execute_phrase true fmt phrase in
      (result, Format.flush_str_formatter ())
    )
  with
  | Syntaxerr.Error _ as e ->
    Error e
  | e ->
    Error e

let initialized = ref false

let read_process_output cmd =
  let ic = Unix.open_process_in cmd in
  let rec read_lines acc =
    try
      let line = input_line ic in
      read_lines (line :: acc)
    with End_of_file ->
      List.rev acc
  in
  let lines = read_lines [] in
  let _ = Unix.close_process_in ic in
  String.concat "\n" lines

let execute_directive directive =
  let lexbuf = Lexing.from_string directive in
  try
    let phrase = !Toploop.parse_toplevel_phrase lexbuf in
    ignore (Toploop.execute_phrase false Format.std_formatter phrase)
  with _ -> ()

let initialize_toplevel project_root =
  if not !initialized then begin
    initialized := true;
    Toploop.initialize_toplevel_env ();
    
    (* Get directives from dune top *)
    let directives_cmd = 
      Printf.sprintf "cd %s && dune top . 2>/dev/null" 
        (Filename.quote project_root)
    in
    
    try
      let output = read_process_output directives_cmd in
      (* Parse and execute each directive line *)
      let lines = String.split_on_char '\n' output in
      List.iter (fun line ->
        let line = String.trim line in
        if String.length line > 0 && line.[0] = '#' then
          execute_directive (line ^ ";;")
      ) lines
    with _ ->
      (* Failed to get directives, continue anyway *)
      ()
  end

let handle project_root args _ctx =
  try
    initialize_toplevel project_root;
    
    (* Evaluate the code *)
    match run_toplevel_phrase args.code with
    | Ok ((success, formatted_output), stdout, stderr) ->
      let output = Buffer.create 256 in
      
      (* Add the formatted output from the toplevel *)
      if String.length formatted_output > 0 then
        Buffer.add_string output formatted_output;
        
      (* Add any additional stdout *)
      if String.length stdout > 0 then begin
        if Buffer.length output > 0 then Buffer.add_char output '\n';
        Buffer.add_string output stdout;
      end;
      
      (* Add any stderr *)
      if String.length stderr > 0 then begin
        if Buffer.length output > 0 then Buffer.add_char output '\n';
        Buffer.add_string output stderr;
      end;
      
      if success then
        Ok (Tool_result.text (Buffer.contents output))
      else
        Ok (Tool_result.error (Buffer.contents output))
    | Error exn ->
      let msg = match exn with
      | Syntaxerr.Error _ ->
        "Syntax error: " ^ Printexc.to_string exn
      | _ ->
        "Error: " ^ Printexc.to_string exn
      in
      Ok (Tool_result.error msg)
  with exn ->
    Ok (Tool_result.error ("Unexpected error: " ^ Printexc.to_string exn))

let register server ~project_root =
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
                `Assoc [ ("code", `Assoc [ ("type", `String "string") ]) ] );
              ("required", `List [ `String "code" ]);
            ]
      end)
    (handle project_root)
