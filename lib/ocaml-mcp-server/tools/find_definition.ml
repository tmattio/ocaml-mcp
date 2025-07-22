open Ocaml_platform_sdk

let name = "ocaml_find_definition"
let description = "Find where a symbol is defined"

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

module Output = struct
  type location = { path : string; line : int; column : int }
  [@@deriving yojson]

  type t = { definition : location option; [@default None] message : string }
  [@@deriving yojson]
end

module Error = struct
  type t =
    | File_not_found of string
    | Read_error of string
    | Merlin_error of string

  let to_string = function
    | File_not_found path -> Printf.sprintf "File not found: %s" path
    | Read_error msg -> Printf.sprintf "Failed to read file: %s" msg
    | Merlin_error msg -> Printf.sprintf "Merlin error: %s" msg
end

let execute ~sw:_ ~env (sdk : Ocaml_platform_sdk.t) (args : Args.t) =
  try
    let fs = Eio.Stdenv.fs env in
    let source_text = Eio.Path.load Eio.Path.(fs / args.Args.file_path) in
    match
      Merlin.find_definition sdk ~source_path:args.Args.file_path ~source_text
        ~line:args.Args.line ~col:args.Args.column
    with
    | Ok (path, pos) ->
        let location =
          {
            Output.path;
            line = pos.pos_lnum;
            column = pos.pos_cnum - pos.pos_bol;
          }
        in
        Ok
          {
            Output.definition = Some location;
            message =
              Printf.sprintf "Definition found at: %s:%d:%d" path pos.pos_lnum
                (pos.pos_cnum - pos.pos_bol);
          }
    | Error err -> Error (Error.Merlin_error err)
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found args.Args.file_path)
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      Error (Error.Read_error (Printexc.to_string exn))
  | exn -> Error (Error.Read_error (Printexc.to_string exn))
