open Ocaml_platform_sdk

let name = "ocaml_module_signature"
let description = "Get the signature of an OCaml module from build artifacts"

module Args = struct
  type t = { module_path : string list } [@@deriving yojson]

  let schema () =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "module_path",
                `Assoc
                  [
                    ("type", `String "array");
                    ("items", `Assoc [ ("type", `String "string") ]);
                  ] );
            ] );
        ("required", `List [ `String "module_path" ]);
      ]
end

module Output = struct
  type t = { signature : string; module_name : string } [@@deriving yojson]
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
