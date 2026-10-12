open Alcotest
module Transport = Mcp_eio.Http

let read_body body = Eio.Buf_read.(parse_exn take_all) body ~max_size:65536

let check_packet label expected actual =
  let json packet = Mcp.Json.of_jsonrpc (Jsonrpc.Packet.yojson_of_t packet) in
  check bool label true (Jsont.Json.equal (json expected) (json actual))

let receive transport ~clock =
  match Transport.recv transport ~clock ~timeout:2. () with
  | Some packet -> packet
  | None -> fail "HTTP transport returned no packet"

let check_status label expected (response, body) =
  check bool label true (Http.Response.status response = expected);
  read_body body

let test_http_transport env () =
  Eio.Switch.run @@ fun sw ->
  let clock = Eio.Stdenv.clock env in
  let endpoint = Uri.of_string "http://127.0.0.1:18081/mcp" in
  let server = Transport.create_server ~sw ~port:18081 () in
  let client =
    Transport.create_client ~sw ~base_url:(Uri.to_string endpoint) env
  in
  let raw_client = Cohttp_eio.Client.make ~https:None (Eio.Stdenv.net env) in
  let post body =
    Cohttp_eio.Client.post ~sw raw_client endpoint
      ~body:(Cohttp_eio.Body.of_string body)
  in
  Fun.protect
    ~finally:(fun () ->
      Transport.close client;
      Transport.close server)
    (fun () ->
      Eio.Time.with_timeout_exn clock 8. (fun () ->
          Eio.Fiber.first
            (fun () -> Transport.run_server server env)
            (fun () ->
              (* Let the server bind its loopback socket before the first call. *)
              Eio.Fiber.yield ();
              let id = `String "local-request" in
              let params =
                Mcp.Json.of_string
                  {|{"name":"echo","arguments":{"text":"café 東京","escaped":"line\n\"quote\"\\path","nested":{"items":[null,true,42,1.25,{"value":"✓"}]}},"_meta":{"local/trace":"sample"}}|}
              in
              let request =
                Mcp.Protocol.outgoing_to_message
                  (Mcp.Protocol.Request (id, "tools/call", Some params))
              in
              Transport.send client request;
              let received_request = receive server ~clock in
              check_packet "native client POST reaches HTTP request queue"
                request received_request;
              let result =
                Mcp.Json.object_
                  [ ("ok", Mcp.Json.bool true); ("echo", params) ]
              in
              let response =
                Mcp.Protocol.outgoing_to_message
                  (Mcp.Protocol.Response (id, Ok result))
              in
              Transport.send server response;
              check_packet "HTTP response reaches native client queue" response
                (receive client ~clock);
              check string "empty POST body" ""
                (check_status "empty POST returns 204" `No_content (post ""));
              ignore
                (check_status "malformed JSON returns 400" `Bad_request
                   (post "{"));
              ignore
                (check_status "unsafe integer returns 400" `Bad_request
                   (post
                      {|{"jsonrpc":"2.0","id":7,"method":"ping","params":{"large":9007199254740992}}|}));
              ignore
                (check_status "GET returns 405" `Method_not_allowed
                   (Cohttp_eio.Client.get ~sw raw_client endpoint));
              check bool "rejected requests do not enter the packet queue" true
                (Option.is_none (Transport.recv server ~clock ())))))

let () =
  Eio_main.run @@ fun env ->
  run "HTTP JSON transport"
    [
      ( "loopback",
        [
          test_case "native packets and invalid HTTP input" `Quick
            (test_http_transport env);
        ] );
    ]
