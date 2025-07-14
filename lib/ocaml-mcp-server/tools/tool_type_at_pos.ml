(** Type at position tool *)

open Eio

module Args = struct
  type t = { file_path : string; line : int; column : int } [@@deriving yojson]

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
          `List [ `String "file_path"; `String "line"; `String "column" ] );
      ]
end

let name = "ocaml_type_at_pos"
let description = "Get type of expression at specific file position"

let execute context args =
  let fs = Stdenv.fs context.Context.env in

  try
    let source_text = Path.load Path.(fs / args.Args.file_path) in
    match
      Merlin_client.type_at_pos context.Context.merlin
        ~source_path:args.Args.file_path ~source_text ~line:args.Args.line
        ~col:args.Args.column
    with
    | Ok (_loc, typ) -> Ok (Mcp_sdk.Tool_result.text typ)
    | Error err -> Ok (Mcp_sdk.Tool_result.error err)
  with
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      let msg =
        match exn with
        | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
            Printf.sprintf "File not found: %s" args.Args.file_path
        | Eio.Io (Eio.Fs.E _, _) ->
            Printf.sprintf "Failed to read file: %s" (Printexc.to_string exn)
        | _ -> Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)
      in
      Ok (Mcp_sdk.Tool_result.error msg)
  | exn ->
      Ok
        (Mcp_sdk.Tool_result.error
           (Printf.sprintf "Failed to read file: %s" (Printexc.to_string exn)))

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
