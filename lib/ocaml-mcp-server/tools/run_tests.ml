let name = "dune_run_tests"
let description = "Run tests defined in the Dune project and report results"

module Args = struct
  type t = { test_names : string list option [@default None] }
  [@@deriving yojson]

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
end

module Output = struct
  type t = { message : string; test_count : int option [@default None] }
  [@@deriving yojson]
end

module Error = struct
  type t = Dune_not_connected | Not_implemented

  let to_string = function
    | Dune_not_connected ->
        "Dune RPC not connected. Please run this command from a dune project."
    | Not_implemented -> "Test execution via Dune RPC is not yet implemented"
end

let execute ~sw:_ ~env:_ (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  match Ocaml_platform_sdk.Dune.progress sdk with
  | Error `Dune_not_initialized -> Error Error.Dune_not_connected
  | Ok _progress ->
      (* TODO: Implement test running via Dune RPC *)
      let tests_str =
        match args.Args.test_names with
        | None -> "all tests"
        | Some names -> String.concat ", " names
      in
      Ok
        {
          Output.message =
            Printf.sprintf "Would run %s (not yet implemented)" tests_str;
          test_count = None;
        }
