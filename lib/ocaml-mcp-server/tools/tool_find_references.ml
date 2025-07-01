(** Find references tool *)

open Mcp_sdk

type args = { file_path : string; line : int; column : int } [@@deriving yojson]

let name = "ocaml/find-references"
let description = "Find all usages of a symbol"

let handle merlin_client args _ctx =
  try
    let source_text =
      let ic = open_in args.file_path in
      let content = really_input_string ic (in_channel_length ic) in
      close_in ic;
      content
    in
    match
      Merlin_client.find_references merlin_client ~source_path:args.file_path
        ~source_text ~line:args.line ~col:args.column
    with
    | Ok locs ->
        let results =
          List.map
            (fun (loc, fname) ->
              Printf.sprintf "%s:%d:%d-%d:%d" fname
                loc.Ocaml_utils.Warnings.loc_start.pos_lnum
                (loc.loc_start.pos_cnum - loc.loc_start.pos_bol)
                loc.loc_end.pos_lnum
                (loc.loc_end.pos_cnum - loc.loc_end.pos_bol))
            locs
        in
        let result_text = String.concat "\n" results in
        Ok (Tool_result.text result_text)
    | Error err -> Ok (Tool_result.error err)
  with exn ->
    Ok
      (Tool_result.error
         (Printf.sprintf "Failed to read file: %s" (Printexc.to_string exn)))

let register server ~merlin_client =
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
    (handle merlin_client)
