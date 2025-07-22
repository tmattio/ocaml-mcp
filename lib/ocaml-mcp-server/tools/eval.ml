let name = "ocaml_eval"
let description = "Evaluate OCaml expressions in project context"

module Args = struct
  type t = { code : string } [@@deriving yojson]

  let schema () =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc [ ("code", `Assoc [ ("type", `String "string") ]) ] );
        ("required", `List [ `String "code" ]);
      ]
end

module Output = struct
  type t = { result : string; stderr : string option [@default None] }
  [@@deriving yojson]
end

module Error = struct
  type t = Evaluation_failed of string | Timeout | Process_error of string

  let to_string = function
    | Evaluation_failed msg -> Printf.sprintf "Evaluation failed: %s" msg
    | Timeout -> "Evaluation timed out after 5 seconds"
    | Process_error msg -> Printf.sprintf "Process error: %s" msg
end

(* Get initialization directives from dune *)
let get_dune_directives env =
  let fs = Eio.Stdenv.fs env in
  let process_mgr = Eio.Stdenv.process_mgr env in

  (* Check if this is a dune project *)
  match Eio.Path.kind ~follow:true Eio.Path.(fs / "dune-project") with
  | `Regular_file | `Directory -> (
      try
        let output_buf = Buffer.create 1024 in

        (* Run dune top with timeout *)
        let output_result =
          try
            Eio.Process.run process_mgr ~executable:"dune"
              [ "dune"; "top"; "." ]
              ~stdout:(Eio.Flow.buffer_sink output_buf);
            Ok (Buffer.contents output_buf)
          with exn -> Error (`Process_failed exn)
        in

        match output_result with
        | Ok output ->
            (* Extract directive lines *)
            let lines = String.split_on_char '\n' output in
            List.filter_map
              (fun line ->
                let line = String.trim line in
                if String.length line > 0 && line.[0] = '#' then
                  Some (line ^ ";;")
                else None)
              lines
        | Error _ -> []
      with _ -> [])
  | _ -> []

(* Evaluate code using ocaml *)
let execute ~sw:_ ~env (_sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let code = args.code in

  (* Get directives *)
  let directives = get_dune_directives env in

  (* Ensure code ends with ;; *)
  let code =
    let trimmed = String.trim code in
    if
      String.length trimmed >= 2
      && String.sub trimmed (String.length trimmed - 2) 2 = ";;"
    then trimmed
    else trimmed ^ ";;"
  in

  (* Create full input *)
  let input = Buffer.create 512 in

  (* Add directives *)
  List.iter
    (fun dir ->
      Buffer.add_string input dir;
      Buffer.add_char input '\n')
    directives;

  (* Add the code *)
  Buffer.add_string input code;
  Buffer.add_char input '\n';

  (* Create pipes for communication *)
  let output_buf = Buffer.create 256 in
  let error_buf = Buffer.create 256 in

  try
    (* Run ocaml *)
    let process_mgr = Eio.Stdenv.process_mgr env in
    Eio.Process.run process_mgr ~executable:"ocaml" [ "ocaml"; "-noprompt" ]
      ~stdin:(Eio.Flow.string_source (Buffer.contents input))
      ~stdout:(Eio.Flow.buffer_sink output_buf)
      ~stderr:(Eio.Flow.buffer_sink error_buf);

    (* Get output *)
    let stdout = Buffer.contents output_buf in
    let stderr = Buffer.contents error_buf in

    (* Clean output - remove version header and prompts *)
    let clean_output s =
      (* First split into lines *)
      let lines = String.split_on_char '\n' s in
      (* Filter each line *)
      let filtered =
        List.filter_map
          (fun line ->
            (* Check various patterns to skip *)
            if String.trim line = "" then None
            else if String.trim line = "#" then None
            else if
              String.length line >= 13 && String.sub line 0 13 = "OCaml version"
            then None
            else if line = "Enter #help;; for help." then None
            else if line = "Enter \"#help;;\" for help." then None
            else Some line)
          lines
      in
      String.concat "\n" filtered |> String.trim
    in

    if String.length stderr > 0 then Error (Error.Evaluation_failed stderr)
    else Ok { Output.result = clean_output stdout; stderr = None }
  with
  | Eio.Exn.Io (Eio.Process.E _, _) ->
      let error_msg = Buffer.contents error_buf in
      let output_msg = Buffer.contents output_buf in
      let full_msg =
        if String.length error_msg > 0 then error_msg
        else if String.length output_msg > 0 then output_msg
        else "Evaluation failed"
      in
      Error (Error.Evaluation_failed full_msg)
  | exn -> Error (Error.Process_error (Printexc.to_string exn))
