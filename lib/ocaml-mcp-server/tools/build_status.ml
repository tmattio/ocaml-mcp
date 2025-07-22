open Ocaml_platform_sdk

let name = "dune_build_status"

let description =
  "Get the current build status from dune, including any errors or warnings"

module Args = struct
  type t = { targets : string list option [@default None] } [@@deriving yojson]

  let schema () =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "targets",
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
  type diagnostic = {
    severity : string;
    file : string;
    line : int;
    column : int;
    message : string;
  }
  [@@deriving yojson]

  type t = { status : string; diagnostics : diagnostic list }
  [@@deriving yojson]
end

module Error = struct
  type t = Dune_not_connected

  let to_string = function
    | Dune_not_connected ->
        "Dune RPC not connected. Please run this command from a dune project."
end

let execute ~sw:_ ~env:_ (sdk : Ocaml_platform_sdk.t) (_args : Args.t) =
  match Dune.diagnostics sdk ~file:"" with
  | Error `Dune_not_initialized -> Error Error.Dune_not_connected
  | Ok diagnostics -> (
      match Dune.progress sdk with
      | Error `Dune_not_initialized -> Error Error.Dune_not_connected
      | Ok progress ->
          let status =
            match progress with
            | Dune.Waiting -> "waiting"
            | Dune.In_progress { complete; remaining; failed } ->
                Printf.sprintf "building (%d/%d completed, %d failed)" complete
                  (complete + remaining) failed
            | Dune.Failed -> "failed"
            | Dune.Interrupted -> "interrupted"
            | Dune.Success ->
                if List.length diagnostics = 0 then "success"
                else "success_with_warnings"
          in

          let formatted_diagnostics =
            List.map
              (fun d ->
                let severity =
                  match d.Dune.severity with
                  | `Error -> "error"
                  | `Warning -> "warning"
                in
                {
                  Output.severity;
                  file = d.file;
                  line = d.line;
                  column = d.column;
                  message = d.message;
                })
              diagnostics
          in

          Ok { Output.status; diagnostics = formatted_diagnostics })
