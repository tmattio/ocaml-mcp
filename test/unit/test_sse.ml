(* Unit tests for the SSE stream parser used by the HTTP transport. *)

module Sse = Mcp_eio.Sse

let feed_all lines =
  let p = Sse.create () in
  List.filter_map (fun line -> Sse.feed_line p line) lines

let data_of events = List.map (fun (e : Sse.event) -> e.data) events

let test_single_event () =
  let events = feed_all [ "data: {\"a\":1}"; "" ] in
  Alcotest.(check (list string)) "one event" [ "{\"a\":1}" ] (data_of events)

let test_multiline_data () =
  let events = feed_all [ "data: line1"; "data: line2"; "" ] in
  Alcotest.(check (list string))
    "data lines joined with newline" [ "line1\nline2" ] (data_of events)

let test_multiple_events () =
  let events = feed_all [ "data: first"; ""; "data: second"; "" ] in
  Alcotest.(check (list string))
    "two events" [ "first"; "second" ] (data_of events)

let test_event_name () =
  let events = feed_all [ "event: message"; "data: x"; "" ] in
  match events with
  | [ { Sse.name = Some "message"; data = "x" } ] -> ()
  | _ -> Alcotest.fail "expected one named event"

let test_comments_and_unknown_fields_ignored () =
  let events = feed_all [ ": comment"; "id: 7"; "retry: 100"; "data: x"; "" ] in
  Alcotest.(check (list string)) "only data kept" [ "x" ] (data_of events)

let test_blank_without_data_emits_nothing () =
  let events = feed_all [ ""; "event: ping"; ""; "" ] in
  Alcotest.(check int) "no events" 0 (List.length events)

let test_crlf_lines () =
  let events = feed_all [ "data: x\r"; "\r" ] in
  Alcotest.(check (list string)) "CR stripped" [ "x" ] (data_of events)

let test_no_space_after_colon () =
  let events = feed_all [ "data:tight"; "" ] in
  Alcotest.(check (list string)) "value kept" [ "tight" ] (data_of events)

let test_field_without_colon () =
  let events = feed_all [ "data"; "" ] in
  Alcotest.(check (list string)) "empty data line" [ "" ] (data_of events)

let test_eof_flush () =
  (* Streams that end without a trailing blank line still yield the last
     event when the reader feeds a final empty line. *)
  let p = Sse.create () in
  let first = Sse.feed_line p "data: tail" in
  Alcotest.(check bool) "not yet emitted" true (first = None);
  match Sse.feed_line p "" with
  | Some { Sse.data = "tail"; _ } -> ()
  | _ -> Alcotest.fail "expected flushed event"

let () =
  Alcotest.run "sse"
    [
      ( "parser",
        [
          Alcotest.test_case "single event" `Quick test_single_event;
          Alcotest.test_case "multiline data" `Quick test_multiline_data;
          Alcotest.test_case "multiple events" `Quick test_multiple_events;
          Alcotest.test_case "event name" `Quick test_event_name;
          Alcotest.test_case "comments and unknown fields" `Quick
            test_comments_and_unknown_fields_ignored;
          Alcotest.test_case "blank without data" `Quick
            test_blank_without_data_emits_nothing;
          Alcotest.test_case "crlf lines" `Quick test_crlf_lines;
          Alcotest.test_case "no space after colon" `Quick
            test_no_space_after_colon;
          Alcotest.test_case "field without colon" `Quick
            test_field_without_colon;
          Alcotest.test_case "eof flush" `Quick test_eof_flush;
        ] );
    ]
