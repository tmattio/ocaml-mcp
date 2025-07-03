(** OCaml REPL evaluation tool *)

open Mcp_sdk
open Eio

type args = { code : string } [@@deriving yojson]

let name = "ocaml/eval"
let description = "Evaluate OCaml expressions in project context"

(* We keep the mutex for thread safety as Toploop has global state *)
let initialized = ref false
let toplevel_mutex = Mutex.create ()

let execute_directive directive =
  let lexbuf = Lexing.from_string directive in
  try
    let phrase = !Toploop.parse_toplevel_phrase lexbuf in
    ignore (Toploop.execute_phrase false Format.std_formatter phrase)
  with _ -> ()

let initialize_toplevel env project_root =
  if not !initialized then (
    initialized := true;
    Toploop.initialize_toplevel_env ();

    (* Only try dune top if we're in a dune project *)
    let dune_project = Filename.concat project_root "dune-project" in
    let fs = Stdenv.fs env in

    (* Check if dune-project exists using Eio *)
    match Path.kind ~follow:true Path.(fs / dune_project) with
    | `Regular_file | `Directory -> (
        (* Get directives from dune top *)
        try
          let process_mgr = Stdenv.process_mgr env in
          let output_buf = Buffer.create 1024 in

          (* Run dune top with timeout using Fiber.first *)
          let output_result =
            Fiber.first
              (fun () ->
                (* Timeout fiber *)
                let clock = Stdenv.mono_clock env in
                Time.Mono.sleep clock 2.0;
                Error `Timeout)
              (fun () ->
                (* Process fiber *)
                try
                  let cwd = Eio.Path.(fs / project_root) in
                  Process.run process_mgr [ "dune"; "top"; "." ] ~cwd
                    ~stdout:(Flow.buffer_sink output_buf);
                  Ok (Buffer.contents output_buf)
                with exn -> Error (`Process_failed exn))
          in

          match output_result with
          | Ok output ->
              (* Parse and execute each directive line *)
              let lines = String.split_on_char '\n' output in
              List.iter
                (fun line ->
                  let line = String.trim line in
                  if String.length line > 0 && line.[0] = '#' then
                    execute_directive (line ^ ";;"))
                lines
          | Error _ ->
              (* Failed to get directives, continue anyway *)
              ()
        with _ ->
          (* Any other failure, continue anyway *)
          ())
    | _ ->
        (* dune-project doesn't exist or isn't accessible, skip dune top *)
        ())

let run_toplevel_phrase code =
  (* Ensure code ends with ;; for proper parsing *)
  let code =
    let trimmed = String.trim code in
    if
      String.length trimmed >= 2
      && String.sub trimmed (String.length trimmed - 2) 2 = ";;"
    then trimmed
    else trimmed ^ ";;"
  in

  let lexbuf = Lexing.from_string code in
  try
    let phrase = !Toploop.parse_toplevel_phrase lexbuf in

    (* Use Format.str_formatter to capture output *)
    let result =
      try
        let success = Toploop.execute_phrase true Format.str_formatter phrase in
        let output = Format.flush_str_formatter () in
        Ok (success, output, "")
      with exn -> Error exn
    in

    result
  with
  | Syntaxerr.Error error ->
      (* Format syntax error with location information *)
      let buf = Buffer.create 256 in
      let fmt = Format.formatter_of_buffer buf in
      Location.report_exception fmt (Syntaxerr.Error error);
      Format.pp_print_flush fmt ();
      Error (Failure (Buffer.contents buf))
  | e -> Error e

let handle env project_root args _ctx =
  Mutex.lock toplevel_mutex;
  try
    let result =
      try
        initialize_toplevel env project_root;

        (* Evaluate the code *)
        match run_toplevel_phrase args.code with
        | Ok (success, stdout, stderr) ->
            let output = Buffer.create 256 in

            (* Add stdout output *)
            if String.length stdout > 0 then Buffer.add_string output stdout;

            (* Add stderr output *)
            if String.length stderr > 0 then (
              if
                Buffer.length output > 0
                && not (Buffer.nth output (Buffer.length output - 1) = '\n')
              then Buffer.add_char output '\n';
              Buffer.add_string output stderr);

            if success then Ok (Tool_result.text (Buffer.contents output))
            else Ok (Tool_result.error (Buffer.contents output))
        | Error exn ->
            let msg =
              match exn with
              | Failure msg -> msg (* Already formatted error message *)
              | _ -> "Error: " ^ Printexc.to_string exn
            in
            Ok (Tool_result.error msg)
      with exn ->
        Ok (Tool_result.error ("Unexpected error: " ^ Printexc.to_string exn))
    in
    Mutex.unlock toplevel_mutex;
    result
  with exn ->
    (* Ensure mutex is unlocked even if an exception occurs *)
    Mutex.unlock toplevel_mutex;
    raise exn

let register server ~sw:_ ~env ~project_root =
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
    (handle env project_root)
