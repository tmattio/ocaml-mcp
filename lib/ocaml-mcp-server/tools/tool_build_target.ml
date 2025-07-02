(** Dune build target tool *)

open Mcp_sdk
open Eio

type args = { targets : string list } [@@deriving yojson]

let name = "dune/build-target"
let description = "Build specific files/libraries/tests"

let handle _sw env _dune_rpc args _ctx =
  let output_lines = ref [] in
  let add_line line = output_lines := line :: !output_lines in

  add_line
    (Printf.sprintf "Building targets: %s" (String.concat " " args.targets));

  let process_mgr = Stdenv.process_mgr env in

  (* Run dune build using Eio.Process *)
  try
    let stdout_buf = Buffer.create 1024 in
    let stderr_buf = Buffer.create 1024 in

    Process.run process_mgr
      ("dune" :: "build" :: args.targets)
      ~stdout:(Flow.buffer_sink stdout_buf)
      ~stderr:(Flow.buffer_sink stderr_buf);

    (* Collect output *)
    let stdout_lines = String.split_on_char '\n' (Buffer.contents stdout_buf) in
    let stderr_lines = String.split_on_char '\n' (Buffer.contents stderr_buf) in

    List.iter (fun line -> if line <> "" then add_line line) stdout_lines;
    List.iter (fun line -> if line <> "" then add_line line) stderr_lines;

    Ok (Tool_result.text (String.concat "\n" (List.rev !output_lines)))
  with exn ->
    (* Check if it's a process exit error *)
    let error_msg =
      match exn with
      | Eio.Exn.Io (Eio.Process.E _, _) -> "Build failed"
      | _ -> Printf.sprintf "Build failed: %s" (Printexc.to_string exn)
    in
    add_line error_msg;
    Ok (Tool_result.error (String.concat "\n" (List.rev !output_lines)))

let register server ~sw ~env ~dune_rpc =
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
                    ( "targets",
                      `Assoc
                        [
                          ("type", `String "array");
                          ("items", `Assoc [ ("type", `String "string") ]);
                        ] );
                  ] );
              ("required", `List [ `String "targets" ]);
            ]
      end)
    (handle sw env dune_rpc)
