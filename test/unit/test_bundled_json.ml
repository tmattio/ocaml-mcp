open Alcotest
module Server = Ocaml_mcp_server

type fixture = {
  name : string;
  tool : (module Server.S);
  args : string;
  output : string;
  properties : (string * string) list;
  required : string list;
}

let fixtures =
  [
    {
      name = "dune_build_status";
      tool = Server.build_status;
      args = {|{"targets":["lib"]}|};
      output =
        {|{"status":"success","diagnostics":[{"severity":"warning","file":"sample.ml","line":2,"column":3,"message":"sample warning"}]}|};
      properties = [ ("targets", "array") ];
      required = [];
    };
    {
      name = "dune_build_target";
      tool = Server.build_target;
      args = {|{"targets":["lib","test"]}|};
      output = {|{"output":"sample build output","success":true}|};
      properties = [ ("targets", "array") ];
      required = [ "targets" ];
    };
    {
      name = "ocaml_eval";
      tool = Server.eval;
      args = {|{"code":"1 + 1"}|};
      output = {|{"result":"2\n","stderr":"sample diagnostic"}|};
      properties = [ ("code", "string") ];
      required = [ "code" ];
    };
    {
      name = "ocaml_find_definition";
      tool = Server.find_definition;
      args = {|{"file_path":"sample.ml","line":2,"column":3}|};
      output =
        {|{"definition":{"path":"definition.ml","line":4,"column":5},"message":"found"}|};
      properties =
        [ ("file_path", "string"); ("line", "integer"); ("column", "integer") ];
      required = [ "file_path"; "line"; "column" ];
    };
    {
      name = "ocaml_find_references";
      tool = Server.find_references;
      args = {|{"file_path":"sample.ml","line":2,"column":3}|};
      output =
        {|{"references":[{"file":"sample.ml","start_line":2,"start_col":3,"end_line":2,"end_col":6}],"count":1}|};
      properties =
        [ ("file_path", "string"); ("line", "integer"); ("column", "integer") ];
      required = [ "file_path"; "line"; "column" ];
    };
    {
      name = "fs_edit";
      tool = Server.fs_edit;
      args =
        {|{"file_path":"sample.ml","old_string":"before","new_string":"after","expected_replacements":1,"replace_all":false}|};
      output =
        {|{"replacements_made":1,"diagnostics":[{"message":"sample warning","severity":"warning","start_line":1,"start_col":0,"end_line":1,"end_col":5}],"formatted":true}|};
      properties =
        [
          ("file_path", "string");
          ("old_string", "string");
          ("new_string", "string");
          ("expected_replacements", "integer");
          ("replace_all", "boolean");
        ];
      required = [ "file_path"; "old_string"; "new_string" ];
    };
    {
      name = "fs_read";
      tool = Server.fs_read;
      args = {|{"file_path":"sample.ml","offset":1,"limit":10}|};
      output =
        {|{"content":"let answer = 42\n","diagnostics":null,"merlin_error":null}|};
      properties =
        [ ("file_path", "string"); ("offset", "integer"); ("limit", "integer") ];
      required = [ "file_path" ];
    };
    {
      name = "fs_write";
      tool = Server.fs_write;
      args = {|{"file_path":"sample.ml","content":"let answer = 42\n"}|};
      output = {|{"path":"sample.ml","formatted":false,"diagnostics":null}|};
      properties = [ ("file_path", "string"); ("content", "string") ];
      required = [ "file_path"; "content" ];
    };
    {
      name = "ocaml_module_signature";
      tool = Server.module_signature;
      args = {|{"module_path":["Sample","Nested"]}|};
      output =
        {|{"signature":"val answer : int","module_name":"Sample.Nested"}|};
      properties = [ ("module_path", "array") ];
      required = [ "module_path" ];
    };
    {
      name = "ocaml_project_structure";
      tool = Server.project_structure;
      args = "null";
      output =
        {|{"project_root":"sample","build_context":"default","components":[{"component_type":["Library"],"name":"sample","directory":"lib","source_dir":"lib","public_name":null,"modules":["Sample"],"dependencies":[]},{"component_type":["Executable"],"name":"main","directory":"bin","source_dir":"bin","public_name":"sample-app","modules":["Main"],"dependencies":["sample"]}]}|};
      properties = [];
      required = [];
    };
    {
      name = "dune_run_tests";
      tool = Server.run_tests;
      args = {|{"test_names":["unit"]}|};
      output = {|{"message":"sample test summary","test_count":2}|};
      properties = [ ("test_names", "array") ];
      required = [];
    };
    {
      name = "ocaml_type_at_pos";
      tool = Server.type_at_pos;
      args = {|{"file_path":"sample.ml","line":2,"column":3}|};
      output =
        {|{"type_info":"int","location":{"start_line":2,"start_col":3,"end_line":2,"end_col":6}}|};
      properties =
        [ ("file_path", "string"); ("line", "integer"); ("column", "integer") ];
      required = [ "file_path"; "line"; "column" ];
    };
  ]

let decode codec value =
  match Jsont.Json.decode codec value with
  | Ok value -> value
  | Error message -> fail message

let encode codec value =
  match Jsont.Json.encode codec value with
  | Ok value -> value
  | Error message -> fail message

let check_json label expected actual =
  check bool label true (Jsont.Json.equal (Mcp.Json.of_string expected) actual)

let round_trip codec source =
  let value = Mcp.Json.of_string source in
  let encoded = encode codec (decode codec value) in
  check_json "typed JSON round trip" source encoded;
  check_json "wire JSON round trip" source
    (Mcp.Json.of_string (Mcp.Json.to_string encoded))

let rejects codec source =
  check bool ("reject " ^ source) true
    (Result.is_error (Jsont.Json.decode codec (Mcp.Json.of_string source)))

let object_fields value =
  match Mcp.Json.fields value with
  | Some fields -> fields
  | None -> fail "Expected a JSON object"

let member name value =
  match Mcp.Json.member name value with
  | Some member -> member
  | None -> fail ("Missing member " ^ name)

let string_value value =
  match Mcp.Json.get_string value with
  | Some value -> value
  | None -> fail "Expected a JSON string"

let string_array value =
  match Mcp.Json.get_array value with
  | Some values -> List.map string_value values
  | None -> fail "Expected a JSON array"

let test_fixture fixture () =
  let module Tool = (val fixture.tool : Server.S) in
  check string "public tool name" fixture.name Tool.name;
  check bool "public description" true (String.length Tool.description > 0);
  round_trip Tool.Args.json fixture.args;
  round_trip Tool.Output.json fixture.output;
  let schema = Tool.Args.schema () in
  check string "schema type" "object" (string_value (member "type" schema));
  let properties = object_fields (member "properties" schema) in
  check (list string) "schema properties"
    (List.sort String.compare (List.map fst fixture.properties))
    (List.sort String.compare (List.map fst properties));
  List.iter
    (fun (name, expected_type) ->
      let property = List.assoc name properties in
      check string (name ^ " schema type") expected_type
        (string_value (member "type" property)))
    fixture.properties;
  check (list string) "required schema properties" fixture.required
    (string_array (member "required" schema));
  check bool "schema wire round trip" true
    (Jsont.Json.equal schema (Mcp.Json.of_string (Mcp.Json.to_string schema)))

let test_required_and_unknown () =
  List.iter
    (fun fixture ->
      let module Tool = (val fixture.tool : Server.S) in
      rejects Tool.Output.json "{}";
      let output_fields = object_fields (Mcp.Json.of_string fixture.output) in
      let extra_output =
        Mcp.Json.object_ (("unknown", Mcp.Json.bool true) :: output_fields)
      in
      rejects Tool.Output.json (Mcp.Json.to_string extra_output);
      match Mcp.Json.fields (Mcp.Json.of_string fixture.args) with
      | None -> rejects Tool.Args.json "{}"
      | Some fields ->
          List.iter
            (fun required ->
              let missing =
                List.filter (fun (name, _) -> name <> required) fields
              in
              rejects Tool.Args.json
                (Mcp.Json.to_string (Mcp.Json.object_ missing)))
            fixture.required;
          let extra =
            Mcp.Json.object_ (("unknown", Mcp.Json.bool true) :: fields)
          in
          rejects Tool.Args.json (Mcp.Json.to_string extra))
    fixtures

let check_normalized codec source expected =
  check_json "optional field normalization" expected
    (encode codec (decode codec (Mcp.Json.of_string source)))

let test_default_options () =
  let module Build = (val Server.build_status : Server.S) in
  check_normalized Build.Args.json "{}" "{}";
  check_normalized Build.Args.json {|{"targets":null}|} "{}";
  let module Read = (val Server.fs_read : Server.S) in
  check_normalized Read.Args.json {|{"file_path":"sample.ml"}|}
    {|{"file_path":"sample.ml"}|};
  check_normalized Read.Args.json
    {|{"file_path":"sample.ml","offset":null,"limit":null}|}
    {|{"file_path":"sample.ml"}|};
  let module Edit = (val Server.fs_edit : Server.S) in
  check_normalized Edit.Args.json
    {|{"file_path":"sample.ml","old_string":"a","new_string":"b","expected_replacements":null,"replace_all":null}|}
    {|{"file_path":"sample.ml","old_string":"a","new_string":"b"}|};
  let module Eval = (val Server.eval : Server.S) in
  check_normalized Eval.Output.json {|{"result":"2","stderr":null}|}
    {|{"result":"2"}|};
  let module Definition = (val Server.find_definition : Server.S) in
  check_normalized Definition.Output.json
    {|{"message":"none","definition":null}|} {|{"message":"none"}|};
  let module Tests = (val Server.run_tests : Server.S) in
  check_normalized Tests.Args.json "{}" "{}";
  check_normalized Tests.Args.json {|{"test_names":null}|} "{}";
  check_normalized Tests.Output.json {|{"message":"none","test_count":null}|}
    {|{"message":"none"}|};
  let module Type_at_pos = (val Server.type_at_pos : Server.S) in
  check_normalized Type_at_pos.Output.json
    {|{"type_info":"int","location":null}|} {|{"type_info":"int"}|}

let test_nullable_members () =
  let module Write = (val Server.fs_write : Server.S) in
  round_trip Write.Output.json
    {|{"path":"sample.ml","formatted":false,"diagnostics":null}|};
  rejects Write.Output.json {|{"path":"sample.ml","formatted":false}|};
  let module Edit = (val Server.fs_edit : Server.S) in
  round_trip Edit.Output.json
    {|{"replacements_made":0,"diagnostics":null,"formatted":false}|};
  rejects Edit.Output.json {|{"replacements_made":0,"formatted":false}|};
  let module Read = (val Server.fs_read : Server.S) in
  rejects Read.Output.json {|{"content":"sample","merlin_error":null}|};
  rejects Read.Output.json {|{"content":"sample","diagnostics":null}|};
  let module Project = (val Server.project_structure : Server.S) in
  rejects Project.Output.json
    {|{"project_root":"sample","build_context":"default","components":[{"component_type":["Library"],"name":"sample","directory":"lib","source_dir":"lib","modules":[],"dependencies":[]}]}|}

let test_integer_fields () =
  List.iter
    (fun tool ->
      let module Tool = (val tool : Server.S) in
      List.iter (rejects Tool.Args.json)
        [
          {|{"file_path":"sample.ml","line":1.5,"column":0}|};
          {|{"file_path":"sample.ml","line":1,"column":0.5}|};
          {|{"file_path":"sample.ml","line":"1","column":0}|};
        ])
    [ Server.find_definition; Server.find_references; Server.type_at_pos ];
  let module Read = (val Server.fs_read : Server.S) in
  rejects Read.Args.json {|{"file_path":"sample.ml","offset":1.5}|};
  rejects Read.Args.json {|{"file_path":"sample.ml","limit":1.5}|};
  let module Edit = (val Server.fs_edit : Server.S) in
  rejects Edit.Args.json
    {|{"file_path":"sample.ml","old_string":"a","new_string":"b","expected_replacements":1.5}|};
  rejects Edit.Output.json
    {|{"replacements_made":1.5,"diagnostics":null,"formatted":false}|};
  let module References = (val Server.find_references : Server.S) in
  rejects References.Output.json {|{"references":[],"count":1.5}|};
  let module Tests = (val Server.run_tests : Server.S) in
  rejects Tests.Output.json {|{"message":"sample","test_count":1.5}|};
  let module Build = (val Server.build_status : Server.S) in
  rejects Build.Output.json
    {|{"status":"success","diagnostics":[{"severity":"warning","file":"sample.ml","line":1.5,"column":0,"message":"sample"}]}|}

let test_project_variants () =
  let module Project = (val Server.project_structure : Server.S) in
  round_trip Project.Args.json "null";
  List.iter
    (fun tag ->
      let source =
        Printf.sprintf
          {|{"project_root":"sample","build_context":"default","components":[{"component_type":%s,"name":"sample","directory":"lib","source_dir":"lib","public_name":null,"modules":[],"dependencies":[]}]}|}
          tag
      in
      rejects Project.Output.json source)
    [ "[]"; {|"Library"|}; {|["Library","Executable"]|}; {|["Unknown"]|} ]

let check_duplicate_member codec source =
  let fields = object_fields (Mcp.Json.of_string source) in
  match fields with
  | [] -> fail "Expected a known record member"
  | (name, _) :: _ ->
      let invalid = (name, Mcp.Json.bool true) in
      let earlier = Mcp.Json.to_string (Mcp.Json.object_ (invalid :: fields)) in
      check_normalized codec earlier source;
      let later =
        Mcp.Json.to_string (Mcp.Json.object_ (fields @ [ invalid ]))
      in
      rejects codec later

let test_duplicate_members () =
  List.iter
    (fun fixture ->
      let module Tool = (val fixture.tool : Server.S) in
      check_duplicate_member Tool.Output.json fixture.output;
      match Mcp.Json.fields (Mcp.Json.of_string fixture.args) with
      | None -> ()
      | Some _ -> check_duplicate_member Tool.Args.json fixture.args)
    fixtures;
  let module Build = (val Server.build_status : Server.S) in
  check_normalized Build.Output.json
    {|{"status":"success","diagnostics":[{"severity":"warning","file":"sample.ml","line":"invalid","line":2,"column":3,"message":"sample"}]}|}
    {|{"status":"success","diagnostics":[{"severity":"warning","file":"sample.ml","line":2,"column":3,"message":"sample"}]}|};
  rejects Build.Output.json
    {|{"status":"success","diagnostics":[{"severity":"warning","file":"sample.ml","line":2,"line":"invalid","column":3,"message":"sample"}]}|};
  let module Project = (val Server.project_structure : Server.S) in
  check_normalized Project.Output.json
    {|{"project_root":"sample","build_context":"default","components":[{"component_type":"invalid","component_type":["Library"],"name":"sample","directory":"lib","source_dir":"lib","public_name":null,"modules":[],"dependencies":[]}]}|}
    {|{"project_root":"sample","build_context":"default","components":[{"component_type":["Library"],"name":"sample","directory":"lib","source_dir":"lib","public_name":null,"modules":[],"dependencies":[]}]}|}

let () =
  run "Bundled tool JSON codecs"
    [
      ( "tools",
        List.map
          (fun fixture -> test_case fixture.name `Quick (test_fixture fixture))
          fixtures );
      ( "compatibility",
        [
          test_case "required members and strict unknown fields" `Quick
            test_required_and_unknown;
          test_case "default optional members" `Quick test_default_options;
          test_case "required nullable members" `Quick test_nullable_members;
          test_case "integer fields reject fractions" `Quick test_integer_fields;
          test_case "unit arguments and variant arrays" `Quick
            test_project_variants;
          test_case "known duplicate members use the last value" `Quick
            test_duplicate_members;
        ] );
    ]
