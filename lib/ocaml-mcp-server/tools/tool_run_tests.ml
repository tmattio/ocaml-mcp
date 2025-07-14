(** Dune run tests tool *)

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

let name = "dune_run_tests"
let description = "Execute tests and report results"

let execute context args =
  match context.Context.dune_rpc with
  | None -> Ok (Mcp_sdk.Tool_result.error "Dune RPC not connected")
  | Some _dune ->
      (* TODO: Implement test running via Dune RPC *)
      let tests_str =
        match args.Args.test_names with
        | None -> "all tests"
        | Some names -> String.concat ", " names
      in
      Ok
        (Mcp_sdk.Tool_result.text
           (Printf.sprintf "Running %s\n(Not yet implemented)" tests_str))

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
