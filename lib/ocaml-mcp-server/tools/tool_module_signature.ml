(** OCaml module signature tool *)

open Mcp_sdk

type args = { module_path : string list } [@@deriving yojson]

let name = "ocaml/module-signature"
let description = "Get the signature of an OCaml module from build artifacts"

let handle project_root args _ctx =
  let src = Logs.Src.create "module-signature" ~doc:"Module signature tool" in
  let module Log = (val Logs.src_log src : Logs.LOG) in
  Log.debug (fun m ->
      m "handle_module_signature called with module_path: %s"
        (String.concat "." args.module_path));

  match
    Ocaml_analysis.get_module_signature ~project_root
      ~module_path:args.module_path
  with
  | Ok signature_text -> Ok (Tool_result.text signature_text)
  | Error err -> Ok (Tool_result.error err)

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
      end)
    (handle project_root)
