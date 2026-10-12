open Ocaml_platform_sdk

let name = "dune_build_status"

let description =
  "Get the current build status from dune, including any errors or warnings"

module Args = struct
  type t = { targets : string list option }

  let json : t Jsont.t =
    Jsont.Object.map (fun targets -> ({ targets } : t))
    |> Jsont.Object.mem "targets"
         (Jsont.option (Jsont.list Jsont.string))
         ~dec_absent:None ~enc_omit:Option.is_none
         ~enc:(fun (v : t) -> v.targets)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  let schema () =
    Mcp.Json.object_
      [
        ("type", Mcp.Json.string "object");
        ( "properties",
          Mcp.Json.object_
            [
              ( "targets",
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
  type diagnostic = {
    severity : string;
    file : string;
    line : int;
    column : int;
    message : string;
  }

  let diagnostic_json : diagnostic Jsont.t =
    Jsont.Object.map (fun severity file line column message ->
        ({ severity; file; line; column; message } : diagnostic))
    |> Jsont.Object.mem "severity" Jsont.string ~enc:(fun (v : diagnostic) ->
        v.severity)
    |> Jsont.Object.mem "file" Jsont.string ~enc:(fun (v : diagnostic) ->
        v.file)
    |> Jsont.Object.mem "line" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.line)
    |> Jsont.Object.mem "column" Mcp.Types.Json_codec.integer_json
         ~enc:(fun (v : diagnostic) -> v.column)
    |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (v : diagnostic) ->
        v.message)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object

  type t = { status : string; diagnostics : diagnostic list }

  let json : t Jsont.t =
    Jsont.Object.map (fun status diagnostics -> ({ status; diagnostics } : t))
    |> Jsont.Object.mem "status" Jsont.string ~enc:(fun (v : t) -> v.status)
    |> Jsont.Object.mem "diagnostics" (Jsont.list diagnostic_json)
         ~enc:(fun (v : t) -> v.diagnostics)
    |> Jsont.Object.error_unknown |> Jsont.Object.finish
    |> Mcp.Types.Json_codec.last_object
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
