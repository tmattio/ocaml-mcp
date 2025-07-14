(** Dune build status tool *)

(* Tool argument types *)
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

let name = "dune_build_status"

let description =
  "Get the current build status from dune, including any errors or warnings"

let execute context _args =
  match context.Context.dune_rpc with
  | None ->
      Ok
        (Mcp_sdk.Tool_result.error
           "Dune RPC not connected. Please run this command from a dune \
            project.")
  | Some dune ->
      (* Get current diagnostics and progress from dune RPC client *)
      let diagnostics = Dune_rpc_client.get_diagnostics dune ~file:"" in
      let progress = Dune_rpc_client.get_progress dune in
      let status_text =
        match progress with
        | Waiting -> "Build waiting..."
        | In_progress { complete; remaining; failed } ->
            Printf.sprintf "Building... (%d/%d completed, %d failed)" complete
              (complete + remaining) failed
        | Failed -> "Build failed"
        | Interrupted -> "Build interrupted"
        | Success ->
            if List.length diagnostics = 0 then "Build successful"
            else "Build completed with warnings"
      in

      let diagnostic_texts =
        List.map
          (fun d ->
            let severity =
              match d.Dune_rpc_client.severity with
              | `Error -> "ERROR"
              | `Warning -> "WARNING"
            in
            Printf.sprintf "[%s] %s:%d:%d: %s" severity d.file d.line d.column
              d.message)
          diagnostics
      in

      let full_text = String.concat "\n" (status_text :: diagnostic_texts) in
      Ok (Mcp_sdk.Tool_result.text full_text)

let register server context =
  Mcp_sdk.Server.tool server name ~description
    ~args:(module Args)
    (fun args _ctx -> execute context args)
