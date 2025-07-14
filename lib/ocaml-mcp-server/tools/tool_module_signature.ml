(** OCaml module signature tool *)

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

let name = "ocaml_module_signature"
let description = "Get the signature of an OCaml module from build artifacts"

let execute context args =
  let src = Logs.Src.create "module-signature" ~doc:"Module signature tool" in
  let module Log = (val Logs.src_log src : Logs.LOG) in
  Log.debug (fun m ->
      m "handle_module_signature called with module_path: %s"
        (String.concat "." args.Args.module_path));

  match
    Ocaml_analysis.get_module_signature ~env:context.Context.env
      ~project_root:context.Context.project_root
      ~module_path:args.Args.module_path
  with
  | Ok signature_text -> Ok (Mcp_sdk.Tool_result.text signature_text)
  | Error err -> Ok (Mcp_sdk.Tool_result.error err)

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
