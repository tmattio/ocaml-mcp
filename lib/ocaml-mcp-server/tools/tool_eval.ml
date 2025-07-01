(** OCaml REPL evaluation tool *)

open Mcp_sdk

type args = { code : string } [@@deriving yojson]

let name = "ocaml/eval"
let description = "Evaluate OCaml expressions in project context"

let handle _project_root _args _ctx =
  (* TODO: Implement REPL integration *)
  Ok (Tool_result.text "OCaml REPL integration not yet implemented")

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
