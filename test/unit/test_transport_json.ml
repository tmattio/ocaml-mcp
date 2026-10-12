open Alcotest
module Json = Mcp.Json
module Protocol = Mcp.Protocol
module Framing = Mcp_eio.Framing

let generic = Json.of_string

let check_json label expected actual =
  check bool label true (Jsont.Json.equal expected actual)

let packet source =
  Jsonrpc.Packet.t_of_yojson (Json.to_jsonrpc (generic source))

let packet_json value = Json.of_jsonrpc (Jsonrpc.Packet.yojson_of_t value)

let parse value =
  match Protocol.parse_message value with
  | Ok message -> message
  | Error message -> fail message

let reader source =
  Eio.Buf_read.of_flow ~max_size:1_000_000 (Eio.Flow.string_source source)

let read_exn reader =
  match Framing.read_packet reader with
  | Some packet -> packet
  | None -> fail "Expected another packet"

let ping = {|{"jsonrpc":"2.0","id":1,"method":"ping"}|}
let initialized = {|{"jsonrpc":"2.0","method":"notifications/initialized"}|}

let test_blank_lines_and_crlf () =
  Eio_main.run (fun _ ->
      let source = reader ("\n\r\n" ^ ping ^ "\r\n\n" ^ initialized ^ "\r\n") in
      check bool "first packet after empty lines" true
        (match parse (read_exn source) with
        | Protocol.Request (`Int 1, Mcp.Request.Ping _) -> true
        | _ -> false);
      check bool "notification after CRLF" true
        (match parse (read_exn source) with
        | Protocol.Notification (Mcp.Notification.Initialized _) -> true
        | _ -> false);
      check bool "EOF after both packets" true
        (Option.is_none (Framing.read_packet source)))

let test_eof () =
  Eio_main.run (fun _ ->
      List.iter
        (fun source ->
          let input = reader source in
          check bool "EOF" true (Option.is_none (Framing.read_packet input));
          check bool "EOF remains stable" true
            (Option.is_none (Framing.read_packet input)))
        [ ""; "\n"; "\r\n\n" ])

let test_invalid_packets () =
  Eio_main.run (fun _ ->
      List.iter
        (fun invalid ->
          let input = reader (invalid ^ "\n" ^ ping ^ "\n") in
          let rejected =
            try
              ignore (Framing.read_packet input);
              false
            with
            | Failure message ->
                let prefix = "Packet parse error:" in
                String.length message >= String.length prefix
                && String.sub message 0 (String.length prefix) = prefix
            | _ -> false
          in
          check bool "malformed line rejected" true rejected;
          check bool "next packet can be read" true
            (match parse (read_exn input) with
            | Protocol.Request (`Int 1, Mcp.Request.Ping _) -> true
            | _ -> false))
        [ "{not-json}"; "true"; {|{"jsonrpc":"2.0","method":7}|} ])

let test_writer_and_utf8 () =
  Eio_main.run (fun _ ->
      let response =
        generic
          {|{"greeting":"日本語, café, €","text":"line\nbreak","nested":[true,null,{"name":"雪"}]}|}
      in
      let outgoing : Protocol.outgoing_message =
        Protocol.Response (`String "utf8", Ok response)
      in
      let original = Protocol.outgoing_to_message outgoing in
      let output = Buffer.create 128 in
      Framing.write_packet (Eio.Flow.buffer_sink output) original;
      let wire = Buffer.contents output in
      check bool "terminal newline" true
        (String.length wire > 0 && wire.[String.length wire - 1] = '\n');
      check int "one physical line" 2
        (List.length (String.split_on_char '\n' wire));
      let roundtrip = read_exn (reader wire) in
      check_json "packet round trip" (packet_json original)
        (packet_json roundtrip);
      match parse roundtrip with
      | Protocol.Response (`String "utf8", Ok actual) ->
          check_json "UTF-8 and escaped newline" response actual
      | _ -> fail "Expected a successful response")

let test_request_bridge () =
  let arguments = generic {|{"text":"hello","count":3,"nested":{"ok":true}}|} in
  let meta = generic {|{"vendor/trace":"雪","progressToken":"run-1"}|} in
  let request : Mcp.Request.t =
    Mcp.Request.ToolsCall
      { name = "echo"; arguments = Some arguments; meta = Some meta }
  in
  let wire =
    request
    |> Protocol.request_to_outgoing ~id:(`String "request-1")
    |> Protocol.outgoing_to_message
  in
  match parse wire with
  | Protocol.Request (`String "request-1", Mcp.Request.ToolsCall actual) ->
      check string "method parameters" "echo" actual.name;
      check bool "arguments present" true (Option.is_some actual.arguments);
      check bool "metadata present" true (Option.is_some actual.meta);
      check_json "native arguments" arguments (Option.get actual.arguments);
      check_json "native metadata" meta (Option.get actual.meta)
  | _ -> fail "Expected a tool call request"

let test_notification_bridge () =
  let notification : Mcp.Notification.t =
    Mcp.Notification.Progress
      {
        progress_token = Mcp.Types.String "9007199254740993";
        progress = 1.5;
        total = Some 2.5;
      }
  in
  let wire =
    notification |> Protocol.notification_to_outgoing
    |> Protocol.outgoing_to_message
  in
  match parse wire with
  | Protocol.Notification (Mcp.Notification.Progress actual) ->
      check bool "numeric text remains a string token" true
        (match actual.progress_token with
        | Mcp.Types.String "9007199254740993" -> true
        | _ -> false);
      check (float 0.) "fractional progress" 1.5 actual.progress;
      check (option (float 0.)) "fractional total" (Some 2.5) actual.total
  | _ -> fail "Expected a progress notification"

let test_response_bridge () =
  let meta = generic {|{"vendor/result":"retained"}|} in
  let structured_content = generic {|{"answer":42,"description":"日本語 €"}|} in
  let response : Mcp.Request.response =
    Mcp.Request.ToolsCall
      {
        content =
          [
            Mcp.Types.Content.Text
              { type_ = "text"; text = "日本語 €"; meta = Some meta };
          ];
        is_error = Some false;
        structured_content = Some structured_content;
        meta = Some meta;
      }
  in
  let wire =
    response
    |> Protocol.response_to_outgoing ~id:(`Int 7)
    |> Protocol.outgoing_to_message
  in
  match parse wire with
  | Protocol.Response (`Int 7, Ok actual) -> (
      let expected = Mcp.Request.response_to_json response in
      check_json "native response fields" expected actual;
      match
        Mcp.Types.Json_codec.decode Mcp.Request.Tools.Call.result_json actual
      with
      | Ok result ->
          check_json "structured result" structured_content
            (Option.get result.structured_content);
          check_json "result metadata" meta (Option.get result.meta)
      | Error message -> fail message)
  | _ -> fail "Expected a successful response"

let test_error_bridge () =
  let wire =
    Protocol.error_to_outgoing ~id:(`Int 8) ~code:(-32602)
      ~message:"bad arguments"
      ~data:(generic {|{"details":"provided"}|})
      ()
    |> Protocol.outgoing_to_message
  in
  let error = Option.get (Json.member "error" (packet_json wire)) in
  check_json "existing optional error data placeholder" Json.null
    (Option.get (Json.member "data" error));
  check bool "error response parses" true
    (match parse wire with
    | Protocol.Response (`Int 8, Error _) -> true
    | _ -> false)

let test_batch_calls () =
  Eio_main.run (fun _ ->
      let wire =
        {|[{"jsonrpc":"2.0","id":"one","method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"}]|}
      in
      check bool "mixed batch preserves order" true
        (match parse (read_exn (reader (wire ^ "\n"))) with
        | Protocol.Batch_request
            [
              Protocol.Request (`String "one", Mcp.Request.Ping _);
              Protocol.Notification (Mcp.Notification.Initialized _);
            ] ->
            true
        | _ -> false);
      let invalid_batch =
        packet
          {|[{"jsonrpc":"2.0","id":1,"method":"missing"},{"jsonrpc":"2.0","id":2,"method":"ping"}]|}
      in
      check bool "invalid method rejects the batch" true
        (Result.is_error (Protocol.parse_message invalid_batch)))

let test_batch_responses () =
  let first = generic {|{"number":1,"text":"one"}|} in
  let second = generic {|{"number":2,"text":"雪"}|} in
  let outgoing : Protocol.outgoing_message =
    Protocol.Batch_response
      [
        Protocol.Response (`Int 1, Ok first);
        Protocol.Response (`String "two", Ok second);
      ]
  in
  let wire = Protocol.outgoing_to_message outgoing in
  match parse wire with
  | Protocol.Batch_response
      [
        Protocol.Response (`Int 1, Ok actual_first);
        Protocol.Response (`String "two", Ok actual_second);
      ] ->
      check_json "first native result" first actual_first;
      check_json "second native result" second actual_second
  | _ -> fail "Expected an ordered batch response"

let test_numeric_wire_safety () =
  Eio_main.run (fun _ ->
      List.iter
        (fun wire ->
          check bool "unsafe integer packet rejected" true
            (try
               ignore (Framing.read_packet (reader (wire ^ "\n")));
               false
             with
            | Failure _ -> true
            | _ -> false))
        [
          {|{"jsonrpc":"2.0","id":9007199254740993,"method":"ping"}|};
          {|{"jsonrpc":"2.0","id":-9007199254740993,"method":"ping"}|};
          {|{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"value":9007199254740993}}}|};
          {|{"jsonrpc":"2.0","id":1,"result":{"value":9223372036854775808123}}|};
        ];
      if Sys.int_size > 53 then begin
        let oversized : Jsonrpc.Packet.t =
          Jsonrpc.Packet.Request
            { id = `Int max_int; method_ = "ping"; params = None }
        in
        let output = Buffer.create 16 in
        check bool "unsafe dependency integer fails before writing" true
          (try
             Framing.write_packet (Eio.Flow.buffer_sink output) oversized;
             false
           with
          | Invalid_argument _ -> true
          | _ -> false);
        check string "no partial packet was written" "" (Buffer.contents output)
      end)

let test_numeric_string_text () =
  Eio_main.run (fun _ ->
      let wire =
        {|{"jsonrpc":"2.0","id":"9007199254740993","method":"tools/call","params":{"name":"echo","arguments":{"literal":"9223372036854775808123","escaped":"say \"9007199254740993\"","nested":["-9007199254740993"]}}}|}
      in
      let actual = read_exn (reader (wire ^ "\n")) in
      check_json "numeric text and escaped quotes survive framing"
        (generic wire) (packet_json actual);
      check bool "string identifier survives protocol bridge" true
        (match parse actual with
        | Protocol.Request (`String "9007199254740993", Mcp.Request.ToolsCall _)
          ->
            true
        | _ -> false))

let test_nonfinite_numbers () =
  List.iter
    (fun source ->
      check bool "nonfinite parsed number rejected" true
        (try
           ignore (generic source);
           false
         with Invalid_argument _ -> true))
    [ "1e999"; "-1e999"; {|{"nested":[1e999]}|} ];
  List.iter
    (fun value ->
      check bool "nonfinite native number rejected before encoding" true
        (try
           ignore (Json.to_string value);
           false
         with Invalid_argument _ -> true))
    [
      Jsont.Number (nan, Jsont.Meta.none);
      Json.array [ Jsont.Number (infinity, Jsont.Meta.none) ];
    ]

let test_fractional_integer_rounding () =
  List.iter
    (fun source ->
      check bool "fractional token cannot silently become an integer" true
        (try
           ignore (generic source);
           false
         with Invalid_argument _ -> true))
    [
      "9007199254740990.5";
      "0.99999999999999999";
      "1e-9999";
      {|{"nested":9007199254740990.5}|};
    ];
  List.iter
    (fun source -> ignore (generic source))
    [ "1.0"; "1e0"; "100e-2"; "0.0e-99999"; "1.25"; "1e20" ]

let test_adapter_errors () =
  check_json "representable dependency integer literal" (generic "42")
    (Json.of_yojson (`Intlit "42"));
  check bool "oversized dependency integer literal rejected" true
    (try
       ignore (Json.of_yojson (`Intlit "9007199254740993"));
       false
     with Invalid_argument _ -> true);
  let unsafe : Jsonrpc.Packet.t =
    Jsonrpc.Packet.Request
      {
        id = `Int 1;
        method_ = "tools/call";
        params =
          Some
            (`Assoc
               [
                 ("name", `String "echo");
                 ("arguments", `Assoc [ ("value", `Int max_int) ]);
               ]);
      }
  in
  if Sys.int_size > 53 then
    List.iter
      (fun packet ->
        check bool "dependency conversion errors follow the result contract"
          true
          (Result.is_error (Protocol.parse_message packet)))
      [
        unsafe;
        Jsonrpc.Packet.Request
          { id = `Int max_int; method_ = "ping"; params = None };
      ]

let test_stdio_lifecycle () =
  Eio_main.run (fun env ->
      let output = Buffer.create 128 in
      let transport =
        Mcp_eio.Stdio.create
          ~stdin:(Eio.Flow.string_source (ping ^ "\n"))
          ~stdout:(Eio.Flow.buffer_sink output)
      in
      let clock = env#clock in
      check bool "stdio receives a packet" true
        (Option.is_some (Mcp_eio.Stdio.recv transport ~clock ()));
      check bool "stdio receives EOF" true
        (Option.is_none (Mcp_eio.Stdio.recv transport ~clock ()));
      let outgoing = packet initialized in
      Mcp_eio.Stdio.send transport outgoing;
      check_json "stdio writes NDJSON" (packet_json outgoing)
        (packet_json (read_exn (reader (Buffer.contents output))));
      Mcp_eio.Stdio.close transport;
      Mcp_eio.Stdio.close transport;
      check bool "closed stdio returns None" true
        (Option.is_none (Mcp_eio.Stdio.recv transport ~clock ()));
      check_raises "closed stdio rejects send" (Failure "Transport is closed")
        (fun () -> Mcp_eio.Stdio.send transport outgoing))

let () =
  run "Native JSON transport"
    [
      ( "protocol and NDJSON",
        [
          test_case "blank lines and CRLF" `Quick test_blank_lines_and_crlf;
          test_case "EOF" `Quick test_eof;
          test_case "malformed packets and recovery" `Quick test_invalid_packets;
          test_case "NDJSON writer and UTF-8" `Quick test_writer_and_utf8;
          test_case "request parameters and metadata bridge" `Quick
            test_request_bridge;
          test_case "notification bridge" `Quick test_notification_bridge;
          test_case "native response bridge" `Quick test_response_bridge;
          test_case "error response compatibility" `Quick test_error_bridge;
          test_case "mixed batch calls" `Quick test_batch_calls;
          test_case "ordered batch responses" `Quick test_batch_responses;
          test_case "unsafe integers at the wire boundary" `Quick
            test_numeric_wire_safety;
          test_case "numeric string text preservation" `Quick
            test_numeric_string_text;
          test_case "nonfinite numeric values" `Quick test_nonfinite_numbers;
          test_case "fractional integer rounding at the wire boundary" `Quick
            test_fractional_integer_rounding;
          test_case "dependency adapter error result" `Quick test_adapter_errors;
          test_case "stdio lifecycle" `Quick test_stdio_lifecycle;
        ] );
    ]
