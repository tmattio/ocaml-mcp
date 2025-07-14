(** OCaml REPL evaluation tool using subprocess *)

open Eio

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

let name = "ocaml_eval"
let description = "Evaluate OCaml expressions in project context"

(* Get initialization directives from dune *)
let get_dune_directives context =
  let fs = Stdenv.fs context.Context.env in
  let dune_project =
    Filename.concat context.Context.project_root "dune-project"
  in

  (* Check if this is a dune project *)
  match Path.kind ~follow:true Path.(fs / dune_project) with
  | `Regular_file | `Directory -> (
      try
        let process_mgr = Stdenv.process_mgr context.Context.env in
        let output_buf = Buffer.create 1024 in

        (* Run dune top with timeout *)
        let output_result =
          Fiber.first
            (fun () ->
              let clock = Stdenv.mono_clock context.Context.env in
              Time.Mono.sleep clock 5.0;
              Error `Timeout)
            (fun () ->
              try
                let cwd = Eio.Path.(fs / context.Context.project_root) in
                Process.run process_mgr [ "dune"; "top"; "." ] ~cwd
                  ~stdout:(Flow.buffer_sink output_buf);
                Ok (Buffer.contents output_buf)
              with exn -> Error (`Process_failed exn))
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
let evaluate_code context code =
  let process_mgr = Stdenv.process_mgr context.Context.env in
  let fs = Stdenv.fs context.Context.env in

  (* Get directives *)
  let directives = get_dune_directives context in

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
    let cwd = Eio.Path.(fs / context.Context.project_root) in
    Process.run process_mgr [ "ocaml"; "-noprompt" ] ~cwd
      ~stdin:(Flow.string_source (Buffer.contents input))
      ~stdout:(Flow.buffer_sink output_buf)
      ~stderr:(Flow.buffer_sink error_buf);

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

    if String.length stderr > 0 then Ok (Mcp_sdk.Tool_result.error stderr)
    else Ok (Mcp_sdk.Tool_result.text (clean_output stdout))
  with
  | Eio.Exn.Io (Eio.Process.E _, _) ->
      let error_msg = Buffer.contents error_buf in
      let output_msg = Buffer.contents output_buf in
      let full_msg =
        if String.length error_msg > 0 then error_msg
        else if String.length output_msg > 0 then output_msg
        else "Evaluation failed"
      in
      Ok (Mcp_sdk.Tool_result.error full_msg)
  | exn ->
      Ok
        (Mcp_sdk.Tool_result.error
           ("Unexpected error: " ^ Printexc.to_string exn))

let execute context args = evaluate_code context args.Args.code

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
