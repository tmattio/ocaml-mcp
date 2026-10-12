open Alcotest
module Request = Mcp.Request
module Notification = Mcp.Notification
module Json = Mcp.Json
module Codec = Mcp.Types.Json_codec

let check_json label expected actual =
  check bool label true (Jsont.Json.equal (Json.of_string expected) actual)

let unwrap = function Ok value -> value | Error message -> fail message
let wire_roundtrip json = Json.of_string (Json.to_string json)

(* Expected output is explicit because optional nulls, ignored members and
   handwritten codecs do not all normalize in the same way. *)
let request_fixtures =
  [
    ( "initialize",
      {|{"protocolVersion":"2025-06-18","capabilities":{"roots":{"listChanged":true}},"clientInfo":{"name":"fixture","version":"1"},"ignored":true}|},
      {|{"protocolVersion":"2025-06-18","capabilities":{"roots":{"listChanged":true}},"clientInfo":{"name":"fixture","version":"1"}}|}
    );
    ( "resources/list",
      {|{"cursor":"next","_meta":{"fixture":true}}|},
      {|{"cursor":"next","_meta":{"fixture":true}}|} );
    ( "resources/read",
      {|{"uri":"file:///fixture","_meta":null}|},
      {|{"uri":"file:///fixture"}|} );
    ( "resources/subscribe",
      {|{"uri":"file:///fixture","_meta":{"subscription":"fixture"}}|},
      {|{"uri":"file:///fixture","_meta":{"subscription":"fixture"}}|} );
    ( "resources/unsubscribe",
      {|{"uri":"file:///fixture"}|},
      {|{"uri":"file:///fixture"}|} );
    ("resources/templates/list", {|{"cursor":null,"ignored":true}|}, {|{}|});
    ("prompts/list", {|{"cursor":"prompt-page"}|}, {|{"cursor":"prompt-page"}|});
    ( "prompts/get",
      {|{"name":"greet","arguments":{"name":"Ada"},"_meta":null}|},
      {|{"name":"greet","arguments":{"name":"Ada"},"_meta":null}|} );
    ( "tools/list",
      {|{"_meta":{"fixture":true}}|},
      {|{"_meta":{"fixture":true}}|} );
    ( "tools/call",
      {|{"name":"echo","arguments":null,"_meta":null}|},
      {|{"name":"echo","arguments":null}|} );
    ( "sampling/createMessage",
      {|{"messages":[{"role":"user","content":{"type":"text","text":"hi"}}],"modelPreferences":{"hints":[{"name":"fixture"}]},"systemPrompt":null,"temperature":0.25,"maxTokens":128,"metadata":{"locale":"en"}}|},
      {|{"messages":[{"role":"user","content":{"type":"text","text":"hi"}}],"modelPreferences":{"hints":[{"name":"fixture"}]},"temperature":0.25,"maxTokens":128,"metadata":{"locale":"en"}}|}
    );
    ( "elicitation/create",
      {|{"message":"Continue?","requestedSchema":{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]},"_meta":null}|},
      {|{"message":"Continue?","requestedSchema":{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]},"_meta":null}|}
    );
    ( "logging/setLevel",
      {|{"level":"warning","_meta":null}|},
      {|{"level":"warning"}|} );
    ( "completion/complete",
      {|{"ref":{"type":"ref/resource","uri":"file:///{path}"},"argument":{"name":"path","value":"fi"},"_meta":null}|},
      {|{"ref":{"type":"ref/resource","uri":"file:///{path}"},"argument":{"name":"path","value":"fi"}}|}
    );
    ("roots/list", {|null|}, {|{}|});
    ("ping", {|{"_meta":{"fixture":true}}|}, {|{"_meta":{"fixture":true}}|});
  ]

let test_request (method_, input, expected) () =
  let request =
    unwrap (Request.of_jsonrpc method_ (Some (Json.of_string input)))
  in
  check string "method dispatch" method_ (Request.method_name request);
  let encoded = Request.params_to_json request in
  check_json "normalized parameters" expected encoded;
  let reparsed =
    unwrap (Request.of_jsonrpc method_ (Some (wire_roundtrip encoded)))
  in
  check_json "parameter roundtrip" expected (Request.params_to_json reparsed)

let result_fixture method_ codec wrap input expected =
  ( method_,
    fun () ->
      let result = unwrap (Codec.decode codec (Json.of_string input)) in
      let encoded = Request.response_to_json (wrap result) in
      check_json "normalized response" expected encoded;
      let reparsed = unwrap (Codec.decode codec (wire_roundtrip encoded)) in
      check_json "response roundtrip" expected
        (Request.response_to_json (wrap reparsed)) )

let result_fixtures =
  [
    result_fixture "initialize" Request.Initialize.result_json
      (fun value -> (Request.Initialize value : Request.response))
      {|{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":null},"resources":{"subscribe":null,"listChanged":false}},"serverInfo":{"name":"fixture","version":"1"},"instructions":null,"_meta":null}|}
      {|{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":null},"resources":{"subscribe":null,"listChanged":false}},"serverInfo":{"name":"fixture","version":"1"}}|};
    result_fixture "resources/list" Request.Resources.List.result_json
      (fun value -> (Request.ResourcesList value : Request.response))
      {|{"resources":[{"uri":"file:///fixture","name":"Fixture","title":null}],"nextCursor":"next","_meta":{"fixture":true}}|}
      {|{"resources":[{"uri":"file:///fixture","name":"Fixture"}],"nextCursor":"next","_meta":{"fixture":true}}|};
    result_fixture "resources/read" Request.Resources.Read.result_json
      (fun value -> (Request.ResourcesRead value : Request.response))
      {|{"contents":[{"uri":"file:///fixture","text":"hello","mimeType":null}]}|}
      {|{"contents":[{"uri":"file:///fixture","text":"hello"}]}|};
    result_fixture "resources/subscribe" Request.Resources.Subscribe.result_json
      (fun value -> (Request.ResourcesSubscribe value : Request.response))
      {|null|} {|null|};
    result_fixture "resources/unsubscribe"
      Request.Resources.Unsubscribe.result_json
      (fun value -> (Request.ResourcesUnsubscribe value : Request.response))
      {|null|} {|null|};
    result_fixture "resources/templates/list"
      Request.Resources.Templates.List.result_json
      (fun value -> (Request.ResourcesTemplatesList value : Request.response))
      {|{"resourceTemplates":[{"uriTemplate":"file:///{path}","name":"Fixture","mimeType":"text/plain"}],"nextCursor":null}|}
      {|{"resourceTemplates":[{"uriTemplate":"file:///{path}","name":"Fixture","mimeType":"text/plain"}]}|};
    result_fixture "prompts/list" Request.Prompts.List.result_json
      (fun value -> (Request.PromptsList value : Request.response))
      {|{"prompts":[{"name":"greet","title":"Greeting","description":"Say hello","arguments":[{"name":"name","required":true}]}],"_meta":null}|}
      {|{"prompts":[{"name":"greet","title":"Greeting","description":"Say hello","arguments":[{"name":"name","required":true}]}]}|};
    result_fixture "prompts/get" Request.Prompts.Get.result_json
      (fun value -> (Request.PromptsGet value : Request.response))
      {|{"description":null,"messages":[{"role":"user","content":{"type":"text","text":"hello"}}],"_meta":{"fixture":true}}|}
      {|{"messages":[{"role":"user","content":{"type":"text","text":"hello"}}],"_meta":{"fixture":true}}|};
    result_fixture "tools/list" Request.Tools.List.result_json
      (fun value -> (Request.ToolsList value : Request.response))
      {|{"tools":[{"name":"echo","inputSchema":{},"annotations":{"readOnlyHint":true},"outputSchema":null}],"nextCursor":null}|}
      {|{"tools":[{"name":"echo","inputSchema":{},"annotations":{"readOnlyHint":true}}]}|};
    result_fixture "tools/call" Request.Tools.Call.result_json
      (fun value -> (Request.ToolsCall value : Request.response))
      {|{"content":[{"type":"text","text":"hello"}],"isError":false,"structuredContent":{"ok":true},"_meta":{"fixture":true}}|}
      {|{"content":[{"type":"text","text":"hello"}],"isError":false,"structuredContent":{"ok":true},"_meta":{"fixture":true}}|};
    result_fixture "sampling/createMessage"
      Request.Sampling.CreateMessage.result_json
      (fun value -> (Request.SamplingCreateMessage value : Request.response))
      {|{"role":"assistant","content":{"type":"text","text":"hello"},"model":"fixture-model","stopReason":"endTurn","_meta":null}|}
      {|{"role":"assistant","content":{"type":"text","text":"hello"},"model":"fixture-model","stopReason":"endTurn"}|};
    result_fixture "elicitation/create" Request.Elicitation.Create.result_json
      (fun value -> (Request.ElicitationCreate value : Request.response))
      {|{"action":"accept","content":{"ok":true},"_meta":{"fixture":true}}|}
      {|{"action":"accept","content":{"ok":true}}|};
    result_fixture "logging/setLevel" Request.Logging.SetLevel.result_json
      (fun value -> (Request.LoggingSetLevel value : Request.response))
      {|{"_meta":null,"ignored":true}|} {|{}|};
    result_fixture "completion/complete" Request.Completion.Complete.result_json
      (fun value -> (Request.CompletionComplete value : Request.response))
      {|{"completion":{"values":["a","b"],"total":2,"hasMore":false},"_meta":null}|}
      {|{"completion":{"values":["a","b"],"total":2,"hasMore":false}}|};
    result_fixture "roots/list" Request.Roots.List.result_json
      (fun value -> (Request.RootsList value : Request.response))
      {|{"roots":[{"uri":"file:///","name":null,"_meta":null}]}|}
      {|{"roots":[{"uri":"file:///"}]}|};
    result_fixture "ping" Request.Ping.result_json
      (fun value -> (Request.Ping value : Request.response))
      {|{"_meta":{"fixture":true}}|} {|{"_meta":{"fixture":true}}|};
  ]

let notification_fixtures =
  [
    ("notifications/initialized", {|null|}, {|{}|});
    ( "notifications/progress",
      {|{"progressToken":"run","progress":1.5,"total":null}|},
      {|{"progressToken":"run","progress":1.5}|} );
    ( "notifications/cancelled",
      {|{"requestId":1,"reason":null}|},
      {|{"requestId":1}|} );
    ( "notifications/resources/updated",
      {|{"uri":"file:///fixture"}|},
      {|{"uri":"file:///fixture"}|} );
    ( "notifications/resources/list_changed",
      {|{"_meta":{"fixture":true}}|},
      {|{"_meta":{"fixture":true}}|} );
    ("notifications/prompts/list_changed", {|true|}, {|{}|});
    ("notifications/tools/list_changed", {|{"_meta":null}|}, {|{}|});
    ("notifications/roots/list_changed", {|{}|}, {|{}|});
    ( "notifications/message",
      {|{"level":"info","logger":null,"data":{"message":"hello","nested":[true,null,2]}}|},
      {|{"level":"info","data":{"message":"hello","nested":[true,null,2]}}|} );
  ]

let test_notification (method_, input, expected) () =
  let notification =
    unwrap (Notification.of_jsonrpc method_ (Some (Json.of_string input)))
  in
  check string "method dispatch" method_ (Notification.method_name notification);
  let encoded = Notification.to_json notification in
  check_json "normalized notification" expected encoded;
  let reparsed =
    unwrap (Notification.of_jsonrpc method_ (Some (wire_roundtrip encoded)))
  in
  check_json "notification roundtrip" expected (Notification.to_json reparsed)

let () =
  run "MCP protocol fixtures"
    [
      ( "request parameters",
        List.map
          (fun ((method_, _, _) as fixture) ->
            test_case method_ `Quick (test_request fixture))
          request_fixtures );
      ( "request results",
        List.map
          (fun (method_, test) -> test_case method_ `Quick test)
          result_fixtures );
      ( "notifications",
        List.map
          (fun ((method_, _, _) as fixture) ->
            test_case method_ `Quick (test_notification fixture))
          notification_fixtures );
    ]
