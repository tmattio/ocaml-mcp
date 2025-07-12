(** Dune run tests tool *)

open Mcp_sdk

type args = { test_names : string list option [@default None] }
[@@deriving yojson]

let name = "dune_run_tests"
let description = "Execute tests and report results"

let handle dune_rpc args _ctx =
  match dune_rpc with
  | None -> Ok (Tool_result.error "Dune RPC not connected")
  | Some _dune ->
      (* TODO: Implement test running via Dune RPC *)
      let tests_str =
        match args.test_names with
        | None -> "all tests"
        | Some names -> String.concat ", " names
      in
      Ok
        (Tool_result.text
           (Printf.sprintf "Running %s\n(Not yet implemented)" tests_str))

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
                    ( "test_names",
                      `Assoc
                        [
                          ("type", `String "array");
                          ("items", `Assoc [ ("type", `String "string") ]);
                        ] );
                  ] );
              ("required", `List []);
            ]
      end)
    (handle dune_rpc)
