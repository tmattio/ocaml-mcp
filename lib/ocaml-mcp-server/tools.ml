(** MCP tool implementations *)

open Mcp.Types

let build_status_tool =
  {
    Tool.name = "dune/build-status";
    title = None;
    description =
      Some
        "Get the current build status from dune, including any errors or \
         warnings";
    input_schema =
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
                      ( "description",
                        `String "Optional list of targets to check status for"
                      );
                    ] );
              ] );
        ];
    output_schema = None;
    annotations = None;
  }

let module_signature_tool =
  {
    Tool.name = "ocaml/module-signature";
    title = None;
    description = Some "Get the signature of an OCaml module using merlin";
    input_schema =
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
                      ( "description",
                        `String
                          "Module path, e.g. [\"List\"] or [\"String\", \
                           \"Map\"]" );
                      ("minItems", `Int 1);
                    ] );
              ] );
          ("required", `List [ `String "module_path" ]);
        ];
    output_schema = None;
    annotations = None;
  }

let all_tools = [ build_status_tool; module_signature_tool ]

let handle_build_status dune_rpc _arguments =
  match dune_rpc with
  | None ->
      {
        Mcp.Request.Tools.Call.content =
          [
            Content.Text
              {
                Content.type_ = "text";
                text =
                  "Dune RPC not connected. Please run this command from a dune \
                   project.";
              };
          ];
        is_error = Some true;
        structured_content = None;
      }
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
      {
        Mcp.Request.Tools.Call.content =
          [ Content.Text { Content.type_ = "text"; text = full_text } ];
        is_error = None;
        structured_content = None;
      }

let format_signature_item item =
  let rec format = function
    | Merlin_client.Value (name, typ) -> Printf.sprintf "val %s : %s" name typ
    | Merlin_client.Type (name, def) -> Printf.sprintf "type %s = %s" name def
    | Merlin_client.Exception (name, typ) ->
        Printf.sprintf "exception %s of %s" name typ
    | Merlin_client.Module (name, contents) ->
        let content_str = String.concat "\n  " (List.map format contents) in
        Printf.sprintf "module %s : sig\n  %s\nend" name content_str
  in
  format item

let handle_module_signature merlin arguments =
  match merlin with
  | None ->
      {
        Mcp.Request.Tools.Call.content =
          [
            Content.Text
              {
                Content.type_ = "text";
                text =
                  "Merlin not available. Please ensure merlin is installed and \
                   configured for your project.";
              };
          ];
        is_error = Some true;
        structured_content = None;
      }
  | Some merlin_client -> (
      match arguments with
      | Some (`Assoc fields) -> (
          match List.assoc_opt "module_path" fields with
          | Some (`List path_parts) ->
              let module_path =
                List.filter_map
                  (function `String s -> Some s | _ -> None)
                  path_parts
              in

              if module_path = [] then
                {
                  Mcp.Request.Tools.Call.content =
                    [
                      Content.Text
                        {
                          Content.type_ = "text";
                          text =
                            "Invalid module_path: must be a non-empty array of \
                             strings";
                        };
                    ];
                  is_error = Some true;
                  structured_content = None;
                }
              else
                let signature =
                  Merlin_client.get_module_signature merlin_client ~module_path
                in
                let formatted =
                  String.concat "\n" (List.map format_signature_item signature)
                in
                {
                  Mcp.Request.Tools.Call.content =
                    [
                      Content.Text { Content.type_ = "text"; text = formatted };
                    ];
                  is_error = None;
                  structured_content = None;
                }
          | _ ->
              {
                Mcp.Request.Tools.Call.content =
                  [
                    Content.Text
                      {
                        Content.type_ = "text";
                        text = "Missing or invalid module_path parameter";
                      };
                  ];
                is_error = Some true;
                structured_content = None;
              })
      | _ ->
          {
            Mcp.Request.Tools.Call.content =
              [
                Content.Text
                  {
                    Content.type_ = "text";
                    text =
                      "Invalid arguments: expected an object with module_path";
                  };
              ];
            is_error = Some true;
            structured_content = None;
          })

let handle_tool_call ~dune_rpc ~merlin params =
  match params.Mcp.Request.Tools.Call.name with
  | "dune/build-status" -> handle_build_status dune_rpc params.arguments
  | "ocaml/module-signature" -> handle_module_signature merlin params.arguments
  | _ ->
      {
        Mcp.Request.Tools.Call.content =
          [
            Content.Text
              {
                Content.type_ = "text";
                text = Printf.sprintf "Unknown tool: %s" params.name;
              };
          ];
        is_error = Some true;
        structured_content = None;
      }
