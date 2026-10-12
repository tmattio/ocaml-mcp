open Ocaml_platform_sdk

let name = "ocaml_module_signature"
let description = "Get the signature of an OCaml module from build artifacts"

module Args = struct
  type t = { module_path : string list }

  let json : t Jsont.t =
    Jsont.Object.map (fun module_path -> ({ module_path } : t))
    |> Jsont.Object.mem "module_path" (Jsont.list Jsont.string)
         ~enc:(fun (v : t) -> v.module_path)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  let schema () =
    Mcp.Json.object_
      [
        ("type", Mcp.Json.string "object");
        ( "properties",
          Mcp.Json.object_
            [
              ( "module_path",
                Mcp.Json.object_
                  [
                    ("type", Mcp.Json.string "array");
                    ( "items",
                      Mcp.Json.object_ [ ("type", Mcp.Json.string "string") ] );
                  ] );
            ] );
        ("required", Mcp.Json.array [ Mcp.Json.string "module_path" ]);
      ]
end

module Output = struct
  type t = { signature : string; module_name : string }

  let json : t Jsont.t =
    Jsont.Object.map (fun signature module_name ->
        ({ signature; module_name } : t))
    |> Jsont.Object.mem "signature" Jsont.string ~enc:(fun (v : t) ->
        v.signature)
    |> Jsont.Object.mem "module_name" Jsont.string ~enc:(fun (v : t) ->
        v.module_name)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
end

module Error = struct
  type t = Analysis_error of string

  let to_string = function
    | Analysis_error msg -> Printf.sprintf "Analysis error: %s" msg
end

let execute ~sw:_ ~env:_ (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  let src = Logs.Src.create "module-signature" ~doc:"Module signature tool" in
  let module Log = (val Logs.src_log src : Logs.LOG) in
  Log.debug (fun m ->
      m "handle_module_signature called with module_path: %s"
        (String.concat "." args.Args.module_path));

  match Analysis.module_signature sdk ~module_path:args.Args.module_path with
  | Ok signature_text ->
      Ok
        {
          Output.signature = signature_text;
          module_name = String.concat "." args.Args.module_path;
        }
  | Error err -> Error (Error.Analysis_error err)
