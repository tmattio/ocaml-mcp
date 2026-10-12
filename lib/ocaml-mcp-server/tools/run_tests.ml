let name = "dune_run_tests"
let description = "Run tests defined in the Dune project and report results"

module Args = struct
  type t = { test_names : string list option }

  let json : t Jsont.t =
    Jsont.Object.map (fun test_names -> ({ test_names } : t))
    |> Jsont.Object.mem "test_names"
         (Jsont.option (Jsont.list Jsont.string))
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : t) -> v.test_names)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  let schema () =
    Mcp.Json.object_
      [
        ("type", Mcp.Json.string "object");
        ( "properties",
          Mcp.Json.object_
            [
              ( "test_names",
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "array");
                    ( "items",
                      Mcp.Json.object_ [ ("type", Mcp.Json.string "string") ] );
                  ] );
            ] );
        ("required", Mcp.Json.array []);
      ]
end

module Output = struct
  type t = { message : string; test_count : int option }

  let json : t Jsont.t =
    Jsont.Object.map (fun message test_count -> ({ message; test_count } : t))
    |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (v : t) -> v.message)
    |> Jsont.Object.mem "test_count"
         (Jsont.option Mcp.Types.Json_codec.integer_json)
         ~dec_absent:None ~enc_omit:Option.is_none ~enc:(fun (v : t) ->
           v.test_count)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
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
