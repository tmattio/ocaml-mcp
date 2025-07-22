let name = "dune_build_target"
let description = "Build specific files/libraries/tests"

module Args = struct
  type t = { targets : string list } [@@deriving yojson]

  let schema () =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "targets",
                `Assoc
                  [
                    ("type", `String "array");
                    ("items", `Assoc [ ("type", `String "string") ]);
                  ] );
            ] );
        ("required", `List [ `String "targets" ]);
      ]
end

module Output = struct
  type t = { output : string; success : bool } [@@deriving yojson]
end

module Error = struct
  type t = Build_failed of string

  let to_string = function
    | Build_failed msg -> Printf.sprintf "Build failed: %s" msg
end

let execute ~sw:_ ~env (_sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let output_lines = ref [] in
  let add_line line = output_lines := line :: !output_lines in

  add_line
    (Printf.sprintf "Building targets: %s"
       (String.concat " " args.Args.targets));

  (* Run dune build using Eio.Process *)
  let stdout_buf = Buffer.create 1024 in
  let stderr_buf = Buffer.create 1024 in

  let build_succeeded =
    try
      (* Run dune build in current directory *)
      let process_mgr = Eio.Stdenv.process_mgr env in
      Eio.Process.run process_mgr ~executable:"dune"
        ("dune" :: "build" :: args.Args.targets)
        ~stdout:(Eio.Flow.buffer_sink stdout_buf)
        ~stderr:(Eio.Flow.buffer_sink stderr_buf);
      true
    with
    | Eio.Exn.Io (Eio.Process.E (Eio.Process.Child_error _), _) ->
        (* Process exited with non-zero status *)
        false
    | _ -> false
  in

  (* Collect output *)
  let stdout_content = Buffer.contents stdout_buf in
  let stderr_content = Buffer.contents stderr_buf in

  let stdout_lines =
    if stdout_content = "" then [] else String.split_on_char '\n' stdout_content
  in
  let stderr_lines =
    if stderr_content = "" then [] else String.split_on_char '\n' stderr_content
  in

  List.iter (fun line -> if line <> "" then add_line line) stdout_lines;
  List.iter (fun line -> if line <> "" then add_line line) stderr_lines;

  if build_succeeded then (
    (* Only add "Success" if dune didn't already output it *)
    let has_success =
      List.exists
        (fun line ->
          String.trim line = "Success" || String.trim line = "Success.")
        !output_lines
    in
    if not has_success then add_line "Success";
    Ok
      {
        Output.output = String.concat "\n" (List.rev !output_lines);
        success = true;
      })
  else Error (Error.Build_failed (String.concat "\n" (List.rev !output_lines)))
