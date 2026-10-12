(** JSON Schema interoperability.

    The validator depends on Yojson.Basic. Keep the conversion at this boundary;
    SDK types and typed argument codecs use Jsont throughout. *)

let to_basic = Mcp.Json.to_basic

(** Simple JSON schema generation from type information *)

let schema_for_build_status_args () =
  Mcp.Json.object_
    [
      ("type", Jsont.Json.string "object");
      ( "properties",
        Mcp.Json.object_
          [
            ( "targets",
              Mcp.Json.object_
                [
                  ("type", Jsont.Json.string "array");
                  ( "items",
                    Mcp.Json.object_ [ ("type", Jsont.Json.string "string") ] );
                  ("description", Jsont.Json.string "List of targets to build");
                ] );
          ] );
      ("required", Jsont.Json.list []);
    ]

let schema_for_module_signature_args () =
  Mcp.Json.object_
    [
      ("type", Jsont.Json.string "object");
      ( "properties",
        Mcp.Json.object_
          [
            ( "module_path",
              Mcp.Json.object_
                [
                  ("type", Jsont.Json.string "array");
                  ( "items",
                    Mcp.Json.object_ [ ("type", Jsont.Json.string "string") ] );
                  ( "description",
                    Jsont.Json.string
                      "Module path (e.g., [\"List\"] for List module)" );
                ] );
          ] );
      ("required", Jsont.Json.list [ Jsont.Json.string "module_path" ]);
    ]
