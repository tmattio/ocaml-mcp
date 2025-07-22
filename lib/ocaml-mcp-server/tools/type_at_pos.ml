open Ocaml_platform_sdk

let name = "ocaml_type_at_pos"

let description =
  "Get type of expression at specific file position in OCaml source files"

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
  type location = {
    start_line : int;
    start_col : int;
    end_line : int;
    end_col : int;
  }
  [@@deriving yojson]

  type t = { type_info : string; location : location option [@default None] }
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
      Merlin.type_at_pos sdk ~source_path:args.Args.file_path ~source_text
        ~line:args.Args.line ~col:args.Args.column
    with
    | Ok (loc, typ) ->
        let location =
          Some
            {
              Output.start_line = loc.Ocaml_utils.Warnings.loc_start.pos_lnum;
              start_col = loc.loc_start.pos_cnum - loc.loc_start.pos_bol;
              end_line = loc.loc_end.pos_lnum;
              end_col = loc.loc_end.pos_cnum - loc.loc_end.pos_bol;
            }
        in
        Ok { Output.type_info = typ; location }
    | Error err -> Error (Error.Merlin_error err)
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) ->
      Error (Error.File_not_found args.Args.file_path)
  | Eio.Io (Eio.Fs.E _, _) as exn ->
      Error (Error.Read_error (Printexc.to_string exn))
  | exn -> Error (Error.Read_error (Printexc.to_string exn))
