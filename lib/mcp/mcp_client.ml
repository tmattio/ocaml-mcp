open Mcp_types
open Mcp_protocol
module Request = Mcp_request
module Notification = Mcp_notification

type notification_handler = {
  on_resources_updated : Notification.Resources.Updated.params -> unit;
  on_resources_list_changed : Notification.Resources.ListChanged.params -> unit;
  on_prompts_list_changed : Notification.Prompts.ListChanged.params -> unit;
  on_tools_list_changed : Notification.Tools.ListChanged.params -> unit;
  on_message : Notification.Message.params -> unit;
}

type request_handler = {
  on_sampling_create_message :
    Request.Sampling.CreateMessage.params ->
    (Request.Sampling.CreateMessage.result, string) result;
  on_elicitation_create :
    Request.Elicitation.Create.params ->
    (Request.Elicitation.Create.result, string) result;
  on_roots_list :
    Request.Roots.List.params -> (Request.Roots.List.result, string) result;
}

type t = {
  mutable next_id : int;
  pending_requests :
    ( Jsonrpc.Id.t,
      (Yojson.Safe.t, Jsonrpc.Response.Error.t) result -> unit )
    Hashtbl.t;
  notification_handler : notification_handler;
  request_handler : request_handler option;
  mutable initialized : bool;
  mutable server_capabilities : Capabilities.server option;
  mutable server_info : ServerInfo.t option;
  client_info : ClientInfo.t;
  client_capabilities : Capabilities.client;
}

let create ?request_handler ~notification_handler ~client_info
    ~client_capabilities () =
  {
    next_id = 0;
    pending_requests = Hashtbl.create 16;
    notification_handler;
    request_handler;
    initialized = false;
    server_capabilities = None;
    server_info = None;
    client_info;
    client_capabilities;
  }

let next_id (client : t) : Jsonrpc.Id.t =
  let id = client.next_id in
  client.next_id <- client.next_id + 1;
  `Int id

let send_request (client : t) (request : Request.t)
    (callback : (Yojson.Safe.t, Jsonrpc.Response.Error.t) result -> unit) :
    outgoing_message =
  let id = next_id client in
  Hashtbl.add client.pending_requests id callback;
  request_to_outgoing ~id request

let send_notification (_client : t) (notification : Notification.t) :
    outgoing_message =
  notification_to_outgoing notification

let handle_notification (client : t) (notification : Notification.t) : unit =
  match notification with
  | Notification.ResourcesUpdated params ->
      client.notification_handler.on_resources_updated params
  | Notification.ResourcesListChanged params ->
      client.notification_handler.on_resources_list_changed params
  | Notification.PromptsListChanged params ->
      client.notification_handler.on_prompts_list_changed params
  | Notification.ToolsListChanged params ->
      client.notification_handler.on_tools_list_changed params
  | Notification.Message params -> client.notification_handler.on_message params
  | _ -> () (* Client doesn't handle other notifications *)

let handle_response (client : t) (id : Jsonrpc.Id.t)
    (response : (Yojson.Safe.t, Jsonrpc.Response.Error.t) result) : unit =
  match Hashtbl.find_opt client.pending_requests id with
  | Some callback ->
      Hashtbl.remove client.pending_requests id;
      callback response
  | None ->
      (* Response without matching request *)
      ()

let handle_request (client : t) (id : Jsonrpc.Id.t) (request : Request.t) :
    outgoing_message option =
  match client.request_handler with
  | None ->
      (* No handler provided, return method not found error *)
      let error =
        {
          Jsonrpc.Response.Error.code =
            Jsonrpc.Response.Error.Code.Other (-32601);
          message = "Client does not handle server requests";
          data = None;
        }
      in
      Some (Response (id, Error error))
  | Some handler -> (
      let result =
        match request with
        | Request.SamplingCreateMessage params ->
            handler.on_sampling_create_message params
            |> Result.map Request.Sampling.CreateMessage.result_to_yojson
        | Request.ElicitationCreate params ->
            handler.on_elicitation_create params
            |> Result.map Request.Elicitation.Create.result_to_yojson
        | Request.RootsList params ->
            handler.on_roots_list params
            |> Result.map Request.Roots.List.result_to_yojson
        | _ -> Error "Client does not handle this request type"
      in
      match result with
      | Ok json -> Some (Response (id, Ok json))
      | Error msg ->
          let error =
            {
              Jsonrpc.Response.Error.code =
                Jsonrpc.Response.Error.Code.Other (-32603);
              message = msg;
              data = None;
            }
          in
          Some (Response (id, Error error)))

let handle_message (client : t) (msg : incoming_message) :
    outgoing_message option =
  match msg with
  | Request (id, request) -> handle_request client id request
  | Notification notification ->
      handle_notification client notification;
      None
  | Response (id, response) ->
      handle_response client id response;
      None
  | Batch_request _ | Batch_response _ -> None (* TODO: Handle batch messages *)

let initialize (client : t) ~protocol_version
    (callback : (Request.Initialize.result, string) result -> unit) :
    outgoing_message =
  let params =
    {
      Request.Initialize.protocol_version;
      capabilities = client.client_capabilities;
      client_info = client.client_info;
    }
  in
  send_request client (Request.Initialize params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Initialize.result_of_yojson json with
          | Ok result ->
              client.initialized <- true;
              client.server_capabilities <- Some result.capabilities;
              client.server_info <- Some result.server_info;
              callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let is_initialized (client : t) : bool = client.initialized

let get_server_capabilities (client : t) : Capabilities.server option =
  client.server_capabilities

let get_server_info (client : t) : ServerInfo.t option = client.server_info

(* Convenience functions for making requests *)

let resources_list (client : t) ?cursor ?meta
    (callback : (Request.Resources.List.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Resources.List.cursor; meta } in
  send_request client (Request.ResourcesList params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Resources.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let resources_read (client : t) ~uri ?meta
    (callback : (Request.Resources.Read.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Resources.Read.uri; meta } in
  send_request client (Request.ResourcesRead params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Resources.Read.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let prompts_list (client : t) ?cursor ?meta
    (callback : (Request.Prompts.List.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Prompts.List.cursor; meta } in
  send_request client (Request.PromptsList params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Prompts.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let prompts_get (client : t) ~name ?arguments ?meta
    (callback : (Request.Prompts.Get.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Prompts.Get.name; arguments; meta } in
  send_request client (Request.PromptsGet params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Prompts.Get.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let tools_list (client : t) ?cursor ?meta
    (callback : (Request.Tools.List.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Tools.List.cursor; meta } in
  send_request client (Request.ToolsList params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Tools.List.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let tools_call (client : t) ~name ?arguments ?meta
    (callback : (Request.Tools.Call.result, string) result -> unit) :
    outgoing_message =
  let params = { Request.Tools.Call.name; arguments; meta } in
  send_request client (Request.ToolsCall params) (fun response ->
      match response with
      | Ok json -> (
          match Request.Tools.Call.result_of_yojson json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error err -> callback (Error err.message))

let default_notification_handler : notification_handler =
  {
    on_resources_updated = (fun _ -> ());
    on_resources_list_changed = (fun _ -> ());
    on_prompts_list_changed = (fun _ -> ());
    on_tools_list_changed = (fun _ -> ());
    on_message = (fun _ -> ());
  }

let default_request_handler : request_handler =
  {
    on_sampling_create_message = (fun _ -> Error "Sampling not implemented");
    on_elicitation_create = (fun _ -> Error "Elicitation not implemented");
    on_roots_list = (fun _ -> Error "Roots list not implemented");
  }
