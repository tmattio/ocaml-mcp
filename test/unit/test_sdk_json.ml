open Alcotest

let generic = Mcp.Json.of_string

let decode codec json =
  match Jsont.Json.decode codec json with
  | Ok value -> value
  | Error message -> fail message

let invoke server request =
  match
    Mcp.Server.handle_message server (Mcp.Protocol.Request (`Int 1, request))
  with
  | Some (Mcp.Protocol.Response (_, Ok json)) -> Ok json
  | Some (Mcp.Protocol.Response (_, Error error)) -> Error error.message
  | _ -> fail "Expected a response"

let initialized server =
  let params =
    decode Mcp.Request.Initialize.params_json
      (generic
         {|{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"sdk-test","version":"1"}}|})
  in
  check bool "initialize succeeds" true
    (Result.is_ok (invoke server (Mcp.Request.Initialize params)));
  server

let call ?meta server name arguments =
  invoke server (Mcp.Request.ToolsCall { name; arguments; meta })

let make_sync () =
  Mcp_sdk.Server.create
    ~server_info:{ name = "sdk-test"; version = "1" }
    ~mcp_logging_config:{ enabled = false; initial_level = None }
    ()

module Args = struct
  type t = { city : string }

  let json =
    Jsont.Object.map (fun city -> { city })
    |> Jsont.Object.mem "city" Jsont.string ~enc:(fun args -> args.city)
    |> Jsont.Object.finish

  let schema () =
    generic
      {|{"type":"object","properties":{"city":{"type":"string","minLength":2,"pattern":"^[A-Z]"}},"required":["city"],"additionalProperties":false}|}
end

let output_schema =
  generic
    {|{"type":"object","properties":{"weather":{"anyOf":[{"type":"null"},{"type":"string","enum":["sunny","rainy"]}]}},"required":["weather"]}|}

let test_sync_input_and_metadata () =
  let sdk = make_sync () in
  let calls = ref 0 in
  let seen_meta = ref None in
  Mcp_sdk.Server.tool sdk "weather"
    ~args:(module Args)
    (fun args ctx ->
      incr calls;
      seen_meta := Mcp_sdk.Context.meta ctx;
      Ok (Mcp_sdk.Tool_result.text args.city));
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  let meta = generic {|{"trace":{"labels":["a",null,true],"count":3}}|} in
  let result =
    call ~meta server "weather" (Some (generic {|{"city":"London"}|}))
  in
  check bool "valid typed input accepted" true (Result.is_ok result);
  check int "handler called once" 1 !calls;
  check bool "native metadata preserved" true
    (match !seen_meta with
    | Some value -> Jsont.Json.equal meta value
    | None -> false);
  List.iter
    (fun source ->
      check bool
        ("input rejected: " ^ source)
        true
        (Result.is_error (call server "weather" (Some (generic source)))))
    [
      {|{"city":"london"}|};
      {|{"city":"L"}|};
      {|{"city":"London","extra":true}|};
      {|{"city":42}|};
      {|{}|};
    ];
  check int "rejected inputs never reach the handler" 1 !calls

let test_sync_output_schema () =
  let sdk = make_sync () in
  let result = ref (generic {|{"weather":"sunny"}|}) in
  Mcp_sdk.Server.tool sdk "weather"
    ~args:(module Args)
    ~output_schema
    (fun _args _ctx -> Ok (Mcp_sdk.Tool_result.structured !result));
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  let args = Some (generic {|{"city":"London"}|}) in
  let accepted = call server "weather" args in
  check bool "valid structured output accepted" true (Result.is_ok accepted);
  (match accepted with
  | Error _ -> ()
  | Ok json ->
      let decoded = decode Mcp.Request.Tools.Call.result_json json in
      check bool "native structured output preserved" true
        (match decoded.structured_content with
        | Some actual -> Jsont.Json.equal !result actual
        | None -> false));
  List.iter
    (fun source ->
      result := generic source;
      check bool
        ("output rejected: " ^ source)
        true
        (Result.is_error (call server "weather" args)))
    [ {|{"weather":"snow"}|}; {|{"weather":42}|}; {|{}|} ]

let test_no_args_output_schema () =
  let sdk = make_sync () in
  Mcp_sdk.Server.tool sdk "weather" ~output_schema (fun () _ctx ->
      Ok (Mcp_sdk.Tool_result.structured (generic {|{"weather":false}|})));
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  check bool "no-argument tools still validate structured output" true
    (Result.is_error (call server "weather" None))

let test_converter_failure () =
  let module Loose_schema = struct
    include Args

    let schema () = generic {|{"type":"object"}|}
  end in
  let sdk = make_sync () in
  let called = ref false in
  Mcp_sdk.Server.tool sdk "weather"
    ~args:(module Loose_schema)
    (fun _args _ctx ->
      called := true;
      Ok (Mcp_sdk.Tool_result.text "unexpected"));
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  check bool "typed codec rejects missing field after schema accepts" true
    (Result.is_error (call server "weather" (Some (generic {|{}|}))));
  check bool "codec failure never reaches handler" false !called

let test_reject_all_schema () =
  let module Reject_all_schema = struct
    include Args

    let schema () = Mcp.Json.bool false
  end in
  let sdk = make_sync () in
  let called = ref false in
  Mcp_sdk.Server.tool sdk "weather"
    ~args:(module Reject_all_schema)
    (fun _args _ctx ->
      called := true;
      Ok (Mcp_sdk.Tool_result.text "unexpected"));
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  check bool "boolean false schemas reject otherwise valid arguments" true
    (Result.is_error
       (call server "weather" (Some (generic {|{"city":"London"}|}))));
  check bool "schema rejection never reaches handler" false !called

let test_prompt_codec () =
  let sdk = make_sync () in
  Mcp_sdk.Server.prompt sdk "weather"
    ~args:(module Args)
    (fun args _ctx ->
      Ok
        {
          Mcp.Request.Prompts.Get.description = Some args.city;
          messages = [];
          meta = None;
        });
  let server = initialized (Mcp_sdk.Server.to_mcp_server sdk) in
  let result =
    invoke server
      (Mcp.Request.PromptsGet
         {
           name = "weather";
           arguments = Some [ ("city", "London") ];
           meta = None;
         })
  in
  check bool "prompt uses native typed codec" true (Result.is_ok result);
  match result with
  | Error _ -> ()
  | Ok json ->
      let result = decode Mcp.Request.Prompts.Get.result_json json in
      check (option string) "typed prompt argument" (Some "London")
        result.description

let test_async_validation () =
  Eio.Switch.run @@ fun sw ->
  let sdk =
    Mcp_sdk_eio.Server.create
      ~server_info:{ name = "async-sdk-test"; version = "1" }
      ~mcp_logging_config:{ enabled = false; initial_level = None }
      ()
  in
  let calls = ref 0 in
  let output = ref (generic {|{"weather":"rainy"}|}) in
  Mcp_sdk_eio.Server.tool sdk "weather"
    ~args:(module Args)
    ~output_schema
    (fun _args ctx ->
      incr calls;
      let promise, resolver = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Fiber.yield ();
          Eio.Promise.resolve resolver
            (Ok
               {
                 (Mcp_sdk.Tool_result.structured !output) with
                 meta = Mcp_sdk_eio.Context.meta ctx;
               }));
      promise);
  let server = initialized (Mcp_sdk_eio.Server.to_mcp_server ~sw sdk) in
  let args = Some (generic {|{"city":"London"}|}) in
  let meta = generic {|{"trace":{"async":true}}|} in
  let result = call ~meta server "weather" args in
  check bool "Promise handler resolves valid output" true (Result.is_ok result);
  (match result with
  | Error _ -> ()
  | Ok json ->
      let result = decode Mcp.Request.Tools.Call.result_json json in
      check bool "Promise result keeps native metadata" true
        (match result.meta with
        | Some value -> Jsont.Json.equal meta value
        | None -> false));
  check bool "Promise tools reject additional input properties" true
    (Result.is_error
       (call server "weather"
          (Some (generic {|{"city":"London","extra":true}|}))));
  check int "invalid input never starts Promise handler" 1 !calls;
  output := generic {|{"weather":"snow"}|};
  check bool "Promise tools validate output after resolving" true
    (Result.is_error (call server "weather" args))

let make_client () =
  let capabilities =
    decode Mcp.Types.Capabilities.client_json (generic {|{}|})
  in
  Mcp_sdk.Client.create
    ~client_info:{ name = "sdk-test"; version = "1" }
    ~client_capabilities:capabilities

let test_client_tool_codec () =
  let client = make_client () in
  match
    Mcp_sdk.Client.tools_call client ~name:"weather"
      ~args:{ Args.city = "London" } ~args_json:Args.json (fun _ -> ())
  with
  | Error message -> fail message
  | Ok (Mcp.Protocol.Request (_, "tools/call", Some json)) ->
      let params = decode Mcp.Request.Tools.Call.params_json json in
      check bool "typed client arguments encoded natively" true
        (match params.arguments with
        | Some args -> Jsont.Json.equal args (generic {|{"city":"London"}|})
        | None -> false)
  | Ok _ -> fail "Expected a tool request"

let test_client_encoding_error () =
  let client = make_client () in
  let decode_only = Jsont.map Jsont.string ~dec:Fun.id in
  let called = ref false in
  let callback _ = called := true in
  check bool "tool encoding errors return before request creation" true
    (Result.is_error
       (Mcp_sdk.Client.tools_call client ~name:"weather" ~args:"London"
          ~args_json:decode_only callback));
  check bool "prompt encoding errors return before request creation" true
    (Result.is_error
       (Mcp_sdk.Client.prompts_get client ~name:"weather" ~args:"London"
          ~args_json:decode_only callback));
  check bool "no response callback for unsent requests" false !called

let test_client_prompt_codec () =
  let client = make_client () in
  let fraction = Mcp.Json.number 0.1 in
  let args =
    Mcp.Json.object_
      [
        ("city", Mcp.Json.string "London");
        ("count", Mcp.Json.number 2.0);
        ("enabled", Mcp.Json.bool true);
        ("fraction", fraction);
        ("exact_fraction", Mcp.Json.string "0.1");
        ("exact_integral", Mcp.Json.string "2.0");
      ]
  in
  (match
     Mcp_sdk.Client.prompts_get client ~name:"weather" ~args
       ~args_json:Jsont.json (fun _ -> ())
   with
  | Error message -> fail message
  | Ok (Mcp.Protocol.Request (_, "prompts/get", Some json)) ->
      let params = decode Mcp.Request.Prompts.Get.params_json json in
      check
        (option (list (pair string string)))
        "prompt strings and JSON values"
        (Some
           [
             ("city", "London");
             ("count", "2");
             ("enabled", "true");
             ("fraction", Mcp.Json.to_string fraction);
             ("exact_fraction", "0.1");
             ("exact_integral", "2.0");
           ])
        params.arguments
  | Ok _ -> fail "Expected a prompt request");
  check bool "prompt requires object-shaped arguments" true
    (Result.is_error
       (Mcp_sdk.Client.prompts_get client ~name:"weather" ~args:"London"
          ~args_json:Jsont.string (fun _ -> ())))

let () =
  Eio_main.run @@ fun _env ->
  run "SDK Jsont"
    [
      ( "sync",
        [
          test_case "input schema and native metadata" `Quick
            test_sync_input_and_metadata;
          test_case "output schema and native structured content" `Quick
            test_sync_output_schema;
          test_case "no-argument output schema" `Quick
            test_no_args_output_schema;
          test_case "typed decoder failures" `Quick test_converter_failure;
          test_case "boolean false input schema" `Quick test_reject_all_schema;
          test_case "typed prompt arguments" `Quick test_prompt_codec;
        ] );
      ( "async",
        [
          test_case "Promise input/output validation" `Quick
            test_async_validation;
        ] );
      ( "client",
        [
          test_case "typed tool argument encoding" `Quick test_client_tool_codec;
          test_case "argument encoding failures" `Quick
            test_client_encoding_error;
          test_case "prompt argument encoding" `Quick test_client_prompt_codec;
        ] );
    ]
