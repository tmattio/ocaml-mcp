(** Simple JSON schema generation from type information *)

let schema_for_build_status_args () =
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
                  ("description", `String "List of targets to build");
                ] );
          ] );
      ("required", `List []);
    ]

let schema_for_module_signature_args () =
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
                    `String "Module path (e.g., [\"List\"] for List module)" );
                ] );
          ] );
      ("required", `List [ `String "module_path" ]);
    ]
