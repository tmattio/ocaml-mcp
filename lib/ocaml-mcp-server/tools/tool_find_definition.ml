(** Find definition tool *)

open Mcp_sdk
open Eio

type args = { file_path : string; line : int; column : int } [@@deriving yojson]

let name = "ocaml_find_definition"
let description = "Find where a symbol is defined"

let handle env merlin_client args _ctx =
  let fs = Stdenv.fs env in

  try
    let source_text = Path.load Path.(fs / args.file_path) in
    match
      Merlin_client.find_definition merlin_client ~source_path:args.file_path
        ~source_text ~line:args.line ~col:args.column
    with
    | Ok (path, pos) ->
        let result =
          Printf.sprintf "Definition found at: %s:%d:%d" path pos.pos_lnum
            pos.pos_cnum
        in
        Ok (Tool_result.text result)
    | Error err -> Ok (Tool_result.error err)
  with
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      let msg =
        match exn with
        | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
            Printf.sprintf "File not found: %s" args.file_path
        | Eio.Io (Eio.Fs.E _, _) ->
            Printf.sprintf "Failed to read file: %s" (Printexc.to_string exn)
        | _ -> Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)
      in
      Ok (Tool_result.error msg)
  | exn ->
      Ok
        (Tool_result.error
           (Printf.sprintf "Failed to read file: %s" (Printexc.to_string exn)))

let register server ~sw:_ ~env ~merlin_client =
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
                    ("file_path", `Assoc [ ("type", `String "string") ]);
                    ("line", `Assoc [ ("type", `String "integer") ]);
                    ("column", `Assoc [ ("type", `String "integer") ]);
                  ] );
              ( "required",
                `List [ `String "file_path"; `String "line"; `String "column" ]
              );
            ]
      end)
    (handle env merlin_client)
