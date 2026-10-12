open Jsonrpc

(* Adapt only at the JSON-RPC dependency boundary. *)
let structured_to_json =
  Option.map (fun value -> Mcp_json.of_jsonrpc (Structured.yojson_of_t value))

let json_to_structured =
  Option.map (fun value ->
      let value = Mcp_json.to_jsonrpc value in
      match value with
      | `Assoc _ | `List _ -> Structured.t_of_yojson value
      | _ -> Structured.t_of_yojson (`Assoc [ ("value", value) ]))

type incoming_message =
  | Request of Id.t * Mcp_request.t
  | Notification of Mcp_notification.t
  | Response of Id.t * (Jsont.json, Response.Error.t) result
  | Batch_request of incoming_message list
  | Batch_response of incoming_message list

type outgoing_message =
  | Request of Id.t * string * Jsont.json option
  | Notification of string * Jsont.json option
  | Response of Id.t * (Jsont.json, Response.Error.t) result
  | Batch_response of outgoing_message list

let validate_id = function
  | `Int value -> ignore (Mcp_json.int value)
  | `String _ -> ()

let parse_request (req : Request.t) : (incoming_message, string) result =
  validate_id req.id;
  let params = structured_to_json req.params in
  match Mcp_request.of_jsonrpc req.method_ params with
  | Ok request -> Ok (Request (req.id, request))
  | Error e -> Error e

let parse_notification (notif : Notification.t) :
    (incoming_message, string) result =
  let params = structured_to_json notif.params in
  match Mcp_notification.of_jsonrpc notif.method_ params with
  | Ok notification -> Ok (Notification notification)
  | Error e -> Error e

let parse_response (resp : Response.t) : incoming_message =
  validate_id resp.id;
  match resp.result with
  | Ok json_result ->
      let result = Mcp_json.of_jsonrpc json_result in
      Response (resp.id, Ok result)
  | Error error -> Response (resp.id, Error error)

let parse_message_unchecked (msg : Packet.t) : (incoming_message, string) result
    =
  match msg with
  | Packet.Request req -> parse_request req
  | Packet.Notification notif -> parse_notification notif
  | Packet.Response resp -> Ok (parse_response resp)
  | Packet.Batch_call calls ->
      let parsed =
        List.map
          (fun call ->
            match call with
            | `Request req -> parse_request req
            | `Notification notif -> parse_notification notif)
          calls
      in
      let errors =
        List.filter_map (function Error e -> Some e | Ok _ -> None) parsed
      in
      if errors <> [] then Error (String.concat "; " errors)
      else
        Ok
          (Batch_request
             (List.filter_map
                (function Ok m -> Some m | Error _ -> None)
                parsed))
  | Packet.Batch_response responses ->
      let parsed = List.map (fun resp -> Ok (parse_response resp)) responses in
      Ok
        (Batch_response
           (List.filter_map
              (function Ok m -> Some m | Error _ -> None)
              parsed))

let parse_message msg =
  try parse_message_unchecked msg
  with Invalid_argument message -> Error message

let make_request ~id method_ params : Packet.t =
  let params = json_to_structured params in
  Packet.Request { Request.id; method_; params }

let make_notification method_ params : Packet.t =
  let params = json_to_structured params in
  Packet.Notification { Notification.method_; params }

let make_response ~id result : Packet.t =
  let json_result = Mcp_json.to_jsonrpc result in
  Packet.Response { Response.id; result = Ok json_result }

let make_error_response ~id error : Packet.t =
  Packet.Response { Response.id; result = Error error }

let rec outgoing_to_message = function
  | Request (id, method_, params) -> make_request ~id method_ params
  | Notification (method_, params) -> make_notification method_ params
  | Response (id, Ok result) -> make_response ~id result
  | Response (id, Error error) -> make_error_response ~id error
  | Batch_response responses ->
      let packets =
        List.map
          (fun msg ->
            match outgoing_to_message msg with
            | Packet.Response r -> r
            | _ -> failwith "Invalid message type in batch response")
          responses
      in
      Packet.Batch_response packets

let request_to_outgoing ~id (request : Mcp_request.t) : outgoing_message =
  let method_ = Mcp_request.method_name request in
  let params = Some (Mcp_request.params_to_json request) in
  Request (id, method_, params)

let notification_to_outgoing (notification : Mcp_notification.t) :
    outgoing_message =
  let method_ = Mcp_notification.method_name notification in
  let params = Some (Mcp_notification.to_json notification) in
  Notification (method_, params)

let response_to_outgoing ~id (response : Mcp_request.response) :
    outgoing_message =
  let result = Mcp_request.response_to_json response in
  Response (id, Ok result)

let error_to_outgoing ~id ~code ~message ?data () : outgoing_message =
  let code = Response.Error.Code.Other code in
  let error =
    match data with
    | None -> Response.Error.make ~code ~message ()
    | Some _ -> Response.Error.make ~code ~message ~data:`Null ()
  in
  Response (id, Error error)
