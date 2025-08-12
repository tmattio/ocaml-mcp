open Alcotest

module Test_mcp_meta = struct
  open Mcp.Meta

  let test_valid_keys () =
    (* Comprehensive test of valid key formats *)
    let valid_meta =
      `Assoc
        [
          (* Names without prefix *)
          ("", `Null);
          (* empty is valid *)
          ("a", `Null);
          (* single letter *)
          ("1", `Null);
          (* single digit *)
          ("simple", `Null);
          ("simple-name", `Null);
          ("simple_name", `Null);
          ("simple.name", `Null);
          ("CamelCase", `Null);
          ("snake_case", `Null);
          ("kebab-case", `Null);
          ("123_mixed.name-456", `Null);
          (* Names with prefixes *)
          ("valid/", `Null);
          (* empty name after slash *)
          ("valid/name", `Null);
          ("a/b", `Null);
          ("valid-label/name", `Null);
          ("valid1.valid2.valid3/name", `Null);
          ("prefix.with.dots/name-with-hyphens_and_underscores", `Null);
        ]
    in
    check (result unit string) "valid keys" (Ok ()) (validate (Some valid_meta))

  let test_invalid_labels () =
    (* Test invalid label formats in prefixes *)
    let test_cases =
      [
        ("1invalid/name", "label starting with digit");
        ("-invalid/name", "label starting with hyphen");
        ("_invalid/name", "label starting with underscore");
        (".invalid/name", "label starting with dot");
        ("invalid-/name", "label ending with hyphen");
        ("invalid_/name", "label ending with underscore");
        ("invalid./name", "label ending with dot");
        ("valid_end/name", "label containing underscore");
        ("valid.1invalid.valid/name", "middle label starting with digit");
        ("valid.-invalid.valid/name", "middle label starting with hyphen");
        ("valid.invalid-.valid/name", "middle label ending with hyphen");
        ( "valid.middle_part.end/name",
          "label containing underscore in dotted prefix" );
      ]
    in
    List.iter
      (fun (key, description) ->
        let meta = `Assoc [ (key, `Null) ] in
        check bool description true (Result.is_error (validate (Some meta))))
      test_cases

  let test_invalid_names () =
    (* Test invalid name formats (without and with prefix) *)
    let invalid_names =
      [
        "-invalid";
        (* starts with hyphen *)
        "_invalid";
        (* starts with underscore *)
        ".invalid";
        (* starts with dot *)
        "invalid-";
        (* ends with hyphen *)
        "invalid_";
        (* ends with underscore *)
        "invalid.";
        (* ends with dot *)
      ]
    in

    (* Test without prefix *)
    List.iter
      (fun name ->
        let meta = `Assoc [ (name, `Null) ] in
        check bool
          (Printf.sprintf "name '%s' should be invalid" name)
          true
          (Result.is_error (validate (Some meta))))
      invalid_names;

    (* Test with prefix *)
    List.iter
      (fun name ->
        let key = "prefix/" ^ name in
        let meta = `Assoc [ (key, `Null) ] in
        check bool
          (Printf.sprintf "prefixed name '%s' should be invalid" name)
          true
          (Result.is_error (validate (Some meta))))
      invalid_names

  let test_reserved_prefixes () =
    (* Test MCP reserved prefix detection *)
    let reserved_keys =
      [
        "modelcontextprotocol.io/";
        "mcp.dev/";
        "api.modelcontextprotocol.org/";
        "tools.mcp.com/";
        "mcp.anything/name";
        "modelcontextprotocol.anything/name";
        "prefix.mcp.label/name";
        "prefix.modelcontextprotocol.label/name";
      ]
    in

    let non_reserved_keys =
      [
        "mcp/name";
        (* mcp alone is not reserved *)
        "modelcontextprotocol/name";
        (* modelcontextprotocol alone is not reserved *)
        "mcp.two.labels/name";
        (* mcp needs to be second-to-last *)
        "mcpfoo.label/name";
        (* not exactly "mcp" *)
        "a.mcp/x";
        (* mcp is last, needs one more label after *)
      ]
    in

    (* Test reserved keys are rejected *)
    List.iter
      (fun key ->
        let meta = `Assoc [ (key, `Null) ] in
        check bool
          (Printf.sprintf "'%s' should be reserved" key)
          true
          (Result.is_error (validate (Some meta))))
      reserved_keys;

    (* Test non-reserved keys are accepted *)
    List.iter
      (fun key ->
        let meta = `Assoc [ (key, `Null) ] in
        check bool
          (Printf.sprintf "'%s' should not be reserved" key)
          true
          (Result.is_ok (validate (Some meta))))
      non_reserved_keys

  let test_slash_handling () =
    (* Test various slash-related edge cases *)
    let invalid_cases =
      [
        ("/", "slash only");
        ("/name", "starts with slash");
        ("prefix//name", "double slash");
        ("//name", "double slash at start");
        ("prefix/middle/name", "multiple slashes");
      ]
    in
    List.iter
      (fun (key, description) ->
        let meta = `Assoc [ (key, `Null) ] in
        check bool description true (Result.is_error (validate (Some meta))))
      invalid_cases

  let test_empty_labels () =
    (* Test that empty labels are properly rejected *)
    let invalid_cases =
      [
        ("mcp./name", "empty label after mcp");
        (".mcp.label/name", "empty label before mcp");
        ("prefix..suffix/name", "empty label in middle");
        ("./name", "empty label at start");
      ]
    in
    List.iter
      (fun (key, description) ->
        let meta = `Assoc [ (key, `Null) ] in
        check bool description true (Result.is_error (validate (Some meta))))
      invalid_cases

  let test_metadata_structure () =
    (* Test metadata structure validation *)
    check (result unit string) "empty meta" (Ok ()) (validate None);

    let empty_object = `Assoc [] in
    check (result unit string) "empty object" (Ok ())
      (validate (Some empty_object));

    let non_object = `List [] in
    check bool "non-object rejected" true
      (Result.is_error (validate (Some non_object)));

    (* Test that validation fails if any key is invalid *)
    let mixed_meta =
      `Assoc
        [
          ("valid", `Null);
          ("also-valid", `Null);
          ("mcp.reserved/name", `Null);
          (* this one is invalid *)
          ("another-valid", `Null);
        ]
    in
    check bool "mixed valid and invalid keys" true
      (Result.is_error (validate (Some mixed_meta)))

  let test_special_cases () =
    (* Test special edge cases not covered elsewhere *)
    let test_cases =
      [
        (* Dots in names vs labels *)
        ("a.b", true, "dots allowed in names");
        ("a.b/name", true, "creates two labels 'a' and 'b'");
        (* Single character cases *)
        ("a", true, "single letter name");
        ("1", true, "single digit name");
        ("a/b", true, "single char prefix and name");
        (* Complex valid cases *)
        ( "very-long-label-name-with-many-characters-123/equally-long-name_with.all-separators",
          true,
          "long complex key" );
        ("a-b-c-1/1a1", true, "multiple hyphens in label, digit-letter in name");
      ]
    in
    List.iter
      (fun (key, should_be_valid, description) ->
        let meta = `Assoc [ (key, `Null) ] in
        let result = validate (Some meta) in
        if should_be_valid then
          check bool description true (Result.is_ok result)
        else check bool description true (Result.is_error result))
      test_cases

  let suite =
    [
      test_case "valid keys" `Quick test_valid_keys;
      test_case "invalid labels" `Quick test_invalid_labels;
      test_case "invalid names" `Quick test_invalid_names;
      test_case "reserved prefixes" `Quick test_reserved_prefixes;
      test_case "slash handling" `Quick test_slash_handling;
      test_case "empty labels" `Quick test_empty_labels;
      test_case "metadata structure" `Quick test_metadata_structure;
      test_case "special cases" `Quick test_special_cases;
    ]
end

let () = run "MCP Tests" [ ("Mcp_meta", Test_mcp_meta.suite) ]
