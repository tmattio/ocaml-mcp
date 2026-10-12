open Alcotest
open Mcp.Types

let decode codec source =
  match Jsont_bytesrw.decode_string codec source with
  | Ok value -> value
  | Error message -> fail message

let generic source = decode Jsont.json source

let check_json label expected actual =
  check bool label true (Jsont.Json.equal (generic expected) actual)

let encode codec value =
  match Jsont.Json.encode codec value with
  | Ok json -> json
  | Error message -> fail message

let rejects codec source =
  check bool source true
    (Result.is_error (Jsont_bytesrw.decode_string codec source))

let test_identifiers () =
  check bool "numeric string stays a string" true
    (match decode request_id_json "\"42\"" with
    | String "42" -> true
    | _ -> false);
  check_json "integer stays numeric" "42" (encode request_id_json (Int 42));
  List.iter (rejects request_id_json)
    [ "1.5"; "null"; "true"; "[]"; "9007199254740992"; "-9007199254740992" ];
  if Sys.int_size > 53 then
    check_json "largest exact identifier" "9007199254740991"
      (encode request_id_json (decode request_id_json "9007199254740991"));
  List.iter (rejects progress_token_json) [ "0.5"; "null"; "9007199254740992" ];
  if Sys.int_size > 53 then
    check bool "large OCaml identifier fails encoding" true
      (Result.is_error (Jsont.Json.encode request_id_json (Int max_int)))

let test_native_number_semantics () =
  (* Native numbers have already become floats, so a typed codec cannot
     recover whether an integral value was written as 1, 1.0, or 1e0.
     The MCP wire parser checks numeric lexemes before that conversion. *)
  List.iter
    (fun source ->
      check bool "direct typed codec accepts an integral native number" true
        (match decode request_id_json source with Int 1 -> true | _ -> false))
    [ "1"; "1.0"; "1e0" ];
  check bool "prebuilt native integral number is accepted" true
    (match Json_codec.decode request_id_json (Jsont.Json.number 1.) with
    | Ok (Int 1) -> true
    | _ -> false);
  check bool "prebuilt native fractional number is rejected" true
    (Result.is_error
       (Json_codec.decode request_id_json (Jsont.Json.number 1.5)));
  if Sys.int_size > 53 then begin
    let rounded = float_of_string "9007199254740990.5" in
    check (float 0.) "native float has already lost the fractional part"
      9007199254740990. rounded;
    check bool "typed input cannot reconstruct the lost lexical fraction" true
      (match Json_codec.decode request_id_json (Jsont.Json.number rounded) with
      | Ok (Int value) -> string_of_int value = "9007199254740990"
      | _ -> false)
  end

let test_record_defaults () =
  let tool =
    decode Tool.json {|{"name":"echo","inputSchema":{},"extra":"ignored"}|}
  in
  check_json "aliases, omission and unknown members"
    {|{"name":"echo","inputSchema":{}}|} (encode Tool.json tool);
  let resource =
    decode Resource.json
      {|{"uri":"x:","name":"x","mimeType":"text/plain","size":2,"_meta":{"vendor/key":true}}|}
  in
  check (option string) "camelCase input" (Some "text/plain") resource.mime_type;
  check_json "camelCase output"
    {|{"uri":"x:","name":"x","mimeType":"text/plain","size":2,"_meta":{"vendor/key":true}}|}
    (encode Resource.json resource);
  rejects Tool.json {|{"name":"missing schema"}|};
  rejects Resource.json {|{"uri":"x:","name":"x","size":1.2}|};
  rejects Resource.json {|{"uri":"x:","name":"x","size":"2"}|}

let test_explicit_null () =
  let value =
    decode Tool.json
      {|{"name":"echo","inputSchema":{},"title":null,"_meta":null}|}
  in
  check_json "optional nulls decode as absent"
    {|{"name":"echo","inputSchema":{}}|} (encode Tool.json value);
  let prompt =
    decode Mcp.Request.Prompts.Get.params_json {|{"name":"greet","_meta":null}|}
  in
  check_json "manual prompt metadata preserves null"
    {|{"name":"greet","_meta":null}|}
    (encode Mcp.Request.Prompts.Get.params_json prompt)

let test_required_option_members () =
  rejects Capabilities.prompts_json "{}";
  rejects Capabilities.tools_json "{}";
  rejects Capabilities.resources_json {|{"subscribe":null}|};
  rejects Capabilities.resources_json {|{"listChanged":null}|};
  let prompts = decode Capabilities.prompts_json {|{"listChanged":null}|} in
  check_json "plain option None is emitted as null" {|{"listChanged":null}|}
    (encode Capabilities.prompts_json prompts);
  let resources =
    decode Capabilities.resources_json {|{"subscribe":null,"listChanged":null}|}
  in
  check_json "both plain options remain present"
    {|{"subscribe":null,"listChanged":null}|}
    (encode Capabilities.resources_json resources);
  rejects Mcp.Request.Tools.Call.params_json {|{"name":"echo"}|};
  let tool_call =
    decode Mcp.Request.Tools.Call.params_json
      {|{"name":"echo","arguments":null,"_meta":null}|}
  in
  check_json "plain arguments retained, defaulted metadata omitted"
    {|{"name":"echo","arguments":null}|}
    (encode Mcp.Request.Tools.Call.params_json tool_call);
  check_json "defaulted client capability options may be absent" "{}"
    (encode Capabilities.client_json (decode Capabilities.client_json "{}"))

let test_generated_duplicate_members () =
  let codec = Capabilities.prompts_json in
  let source = {|{"listChanged":true,"listChanged":false}|} in
  check (option bool) "known member uses last occurrence" (Some false)
    (decode codec source).list_changed;
  check (option bool) "generic JSON bridge keeps the same duplicate rule"
    (Some false)
    (match Json_codec.decode codec (generic source) with
    | Ok value -> value.list_changed
    | Error message -> fail message);
  let tool =
    decode Tool.json
      {|{"name":"first","name":"last","inputSchema":{},"title":"first","title":null}|}
  in
  check string "required known member uses last occurrence" "last" tool.name;
  check_json "defaulted duplicate null omits the member"
    {|{"name":"last","inputSchema":{}}|} (encode Tool.json tool);
  let params =
    decode OnlyMetaParams.json
      {|{"_meta":{"value":"first"},"_meta":{"value":"last"}}|}
  in
  check_json "metadata-only PPX shadow uses last occurrence"
    {|{"_meta":{"value":"last"}}|}
    (encode OnlyMetaParams.json params);
  check_json "last duplicate metadata null restores empty parameters" "{}"
    (encode OnlyMetaParams.json
       (decode OnlyMetaParams.json {|{"_meta":{"value":"first"},"_meta":null}|}));
  check (option bool) "malformed earlier known duplicate is ignored"
    (Some false)
    (decode codec {|{"listChanged":"bad","listChanged":false}|}).list_changed;
  let source =
    {|{"name":false,"name":"last","inputSchema":{},"title":false,"title":null}|}
  in
  check_json "malformed earlier required and defaulted members are ignored"
    {|{"name":"last","inputSchema":{}}|}
    (encode Tool.json (decode Tool.json source));
  check_json "native JSON bridge ignores malformed earlier duplicates too"
    {|{"name":"last","inputSchema":{}}|}
    (match Json_codec.decode Tool.json (generic source) with
    | Ok value -> encode Tool.json value
    | Error message -> fail message);
  rejects codec {|{"listChanged":true,"listChanged":"bad"}|};
  rejects Tool.json {|{"name":"first","name":false,"inputSchema":{}}|};
  rejects Tool.json
    {|{"name":"first","inputSchema":{},"title":null,"title":false}|}

let test_handwritten_duplicate_members () =
  let prompt =
    decode Mcp.Request.Prompts.Get.params_json
      {|{"name":"first","name":false,"arguments":{"value":"first"},"arguments":false,"_meta":null,"_meta":{"value":"last"}}|}
  in
  check_json "manual prompt members use first occurrence"
    {|{"name":"first","arguments":{"value":"first"},"_meta":null}|}
    (encode Mcp.Request.Prompts.Get.params_json prompt);
  let params =
    decode Mcp.Request.Elicitation.Create.params_json
      {|{"message":"first","message":false,"requestedSchema":{"type":"object","properties":{},"required":[]},"requestedSchema":false,"_meta":null,"_meta":false}|}
  in
  check string "manual elicitation message uses first occurrence" "first"
    params.message;
  check_json "manual elicitation metadata preserves first null" "null"
    (Option.get params.meta);
  let result =
    decode Mcp.Request.Elicitation.Create.result_json
      {|{"action":"accept","action":false,"content":{"value":1},"content":false,"_meta":null,"_meta":false}|}
  in
  check_json "manual elicitation result uses first members"
    {|{"action":"accept","content":{"value":1}}|}
    (encode Mcp.Request.Elicitation.Create.result_json result);
  check_json "manual result metadata keeps the first null" "null"
    (Option.get result.meta);
  let schema =
    decode ElicitationSchema.json
      {|{"type":"object","type":"array","properties":{"value":{"type":"string"}},"properties":false,"required":["value"],"required":false}|}
  in
  check_json "manual schema members use first occurrence"
    {|{"type":"object","properties":{"value":{"type":"string"}},"required":["value"]}|}
    (encode ElicitationSchema.json schema)

let test_only_meta () =
  List.iter
    (fun source ->
      check_json "permissive empty metadata" "{}"
        (encode OnlyMetaParams.json (decode OnlyMetaParams.json source)))
    [ "null"; "true"; "[]"; "42"; "{}"; {|{"_meta":null}|} ];
  check_json "metadata retained" {|{"_meta":{"custom":1}}|}
    (encode OnlyMetaParams.json
       (decode OnlyMetaParams.json {|{"_meta":{"custom":1},"other":2}|}))

let test_content () =
  List.iter
    (fun source ->
      check_json "content round trip" source
        (encode Content.json (decode Content.json source)))
    [
      {|{"type":"text","text":"hello"}|};
      {|{"type":"image","data":"AA==","mimeType":"image/png"}|};
      {|{"type":"audio","data":"AA==","mimeType":"audio/wav"}|};
      {|{"type":"resource_link","uri":"file:///x","name":"x"}|};
      {|{"type":"resource","resource":{"uri":"file:///x","text":"value"}}|};
    ];
  List.iter (rejects Content.json)
    [
      "{}";
      "null";
      {|{"type":false}|};
      {|{"type":"unknown"}|};
      {|{"type":"text"}|};
    ]

let test_schema_dispatch () =
  List.iter
    (fun source ->
      check_json "schema round trip" source
        (encode PrimitiveSchema.json (decode PrimitiveSchema.json source)))
    [
      {|{"type":"string","minLength":1,"maxLength":4}|};
      {|{"type":"string","enum":["a","b"],"enumNames":["A","B"]}|};
      {|{"type":"integer","minimum":0,"maximum":9}|};
      {|{"type":"number","minimum":0}|};
      {|{"type":"boolean","default":false}|};
    ];
  List.iter
    (rejects PrimitiveSchema.json)
    [ "{}"; {|{"type":"array"}|}; {|{"type":"string","enum":null}|} ];
  let source =
    {|{"type":"object","properties":{"b":{"type":"boolean"},"a":{"type":"string"}},"required":["b"]}|}
  in
  let schema = decode ElicitationSchema.json source in
  check (list string) "property order" [ "b"; "a" ]
    (List.map fst schema.properties);
  check_json "elicitation schema" source (encode ElicitationSchema.json schema);
  rejects ElicitationSchema.json
    {|{"type":"array","properties":{},"required":[]}|}

let test_prompt_arguments () =
  let codec = Mcp.Request.Prompts.Get.params_json in
  let valid =
    {|{"name":"greet","arguments":{"name":"Ada","role":"developer"}}|}
  in
  check_json "string argument object" valid (encode codec (decode codec valid));
  List.iter
    (fun source ->
      check_json "invalid arguments ignored" {|{"name":"greet"}|}
        (encode codec (decode codec source)))
    [
      {|{"name":"greet","arguments":null}|};
      {|{"name":"greet","arguments":[]}|};
      {|{"name":"greet","arguments":{"name":42}}|};
    ]

let test_elicitation_result () =
  let codec = Mcp.Request.Elicitation.Create.result_json in
  let value =
    decode codec
      {|{"action":"accept","content":{"answer":true},"_meta":{"custom":1}}|}
  in
  check bool "metadata decoded" true (Option.is_some value.meta);
  check_json "existing result metadata omission"
    {|{"action":"accept","content":{"answer":true}}|} (encode codec value);
  List.iter
    (fun source ->
      check_json "invalid content ignored" {|{"action":"decline"}|}
        (encode codec (decode codec source)))
    [
      {|{"action":"decline","content":null}|};
      {|{"action":"decline","content":[]} |};
    ]

let test_completion_reference () =
  check_json "resource template keeps existing wire alias"
    {|{"type":"ref/resource","uri":"file:///{path}"}|}
    (encode CompletionReference.json
       (CompletionReference.ResourceTemplate "file:///{path}"));
  check bool "wire resource decodes as Resource" true
    (match
       decode CompletionReference.json
         {|{"type":"ref/resource","uri":"file:///x"}|}
     with
    | Resource "file:///x" -> true
    | _ -> false);
  rejects CompletionReference.json {|{"type":"ref/prompt"}|}

let test_protocol_dispatch () =
  let request = Mcp.Request.of_jsonrpc "ping" None in
  check bool "missing ping parameters" true (Result.is_ok request);
  check bool "unknown request" true
    (Result.is_error (Mcp.Request.of_jsonrpc "missing" None));
  check bool "initialized notification" true
    (Result.is_ok
       (Mcp.Notification.of_jsonrpc "notifications/initialized" None));
  check bool "missing required progress" true
    (Result.is_error
       (Mcp.Notification.of_jsonrpc "notifications/progress" None));
  let source = {|{"progressToken":"run","progress":1.5,"total":3}|} in
  let progress = decode Mcp.Notification.Progress.params_json source in
  check_json "fractional progress allowed" source
    (encode Mcp.Notification.Progress.params_json progress);
  rejects Mcp.Notification.Progress.params_json
    {|{"progressToken":1,"progress":null}|}

let test_misc_records () =
  List.iter
    (fun level ->
      check string "log level" level
        (decode Jsont.string
           (match
              Jsont_bytesrw.encode_string LogLevel.json
                (decode LogLevel.json ("\"" ^ level ^ "\""))
            with
           | Ok value -> value
           | Error message -> fail message)))
    [
      "debug";
      "info";
      "notice";
      "warning";
      "error";
      "critical";
      "alert";
      "emergency";
    ];
  rejects LogLevel.json "\"verbose\"";
  let error =
    decode error_json
      {|{"code":-32600,"message":"bad request","data":{"detail":true}}|}
  in
  check_json "error payload"
    {|{"code":-32600,"message":"bad request","data":{"detail":true}}|}
    (encode error_json error);
  let caps =
    decode Capabilities.server_json
      {|{"resources":{"subscribe":true,"listChanged":false},"tools":{"listChanged":true}}|}
  in
  check_json "capability aliases"
    {|{"resources":{"subscribe":true,"listChanged":false},"tools":{"listChanged":true}}|}
    (encode Capabilities.server_json caps)

let () =
  run "Native JSON codecs"
    [
      ( "core",
        [
          test_case "identifiers and numeric safety" `Quick test_identifiers;
          test_case "native numbers and wire lexemes" `Quick
            test_native_number_semantics;
          test_case "record defaults and aliases" `Quick test_record_defaults;
          test_case "explicit null behavior" `Quick test_explicit_null;
          test_case "required and defaulted option members" `Quick
            test_required_option_members;
          test_case "generated duplicate members" `Quick
            test_generated_duplicate_members;
          test_case "handwritten duplicate members" `Quick
            test_handwritten_duplicate_members;
          test_case "permissive metadata params" `Quick test_only_meta;
          test_case "content variants" `Quick test_content;
          test_case "schema variants and dictionaries" `Quick
            test_schema_dispatch;
          test_case "prompt argument tolerance" `Quick test_prompt_arguments;
          test_case "elicitation result compatibility" `Quick
            test_elicitation_result;
          test_case "completion reference aliases" `Quick
            test_completion_reference;
          test_case "request and notification dispatch" `Quick
            test_protocol_dispatch;
          test_case "other typed records" `Quick test_misc_records;
        ] );
    ]
