(** Dune build target tool *)

open Mcp_sdk

type args = { targets : string list } [@@deriving yojson]

let name = "dune/build-target"
let description = "Build specific files/libraries/tests"

let handle _dune_rpc args _ctx =
  let targets_str = String.concat " " args.targets in
  let output_lines = ref [] in
  let add_line line = output_lines := line :: !output_lines in

  add_line (Printf.sprintf "Building targets: %s" targets_str);

  (* Execute dune build command with --no-lock to work alongside watch mode *)
  let cmd = Printf.sprintf "dune build %s 2>&1" targets_str in
  let ic = Unix.open_process_in cmd in
  let rec read_output () =
    try
      let line = input_line ic in
      add_line line;
      read_output ()
    with End_of_file -> ()
  in
  read_output ();

  match Unix.close_process_in ic with
  | Unix.WEXITED 0 ->
      Ok (Tool_result.text (String.concat "\n" (List.rev !output_lines)))
  | Unix.WEXITED _code ->
      Ok (Tool_result.error (String.concat "\n" (List.rev !output_lines)))
  | _ ->
      add_line "Build was interrupted";
      Ok (Tool_result.error (String.concat "\n" (List.rev !output_lines)))

let register server ~dune_rpc =
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
    (handle dune_rpc)
