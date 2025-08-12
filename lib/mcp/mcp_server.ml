open Mcp_types
open Mcp_protocol
module Request = Mcp_request
module Notification = Mcp_notification
module Meta = Mcp_meta

type handler = {
  on_initialize :
    Request.Initialize.params -> (Request.Initialize.result, string) result;
  on_resources_list :
    Request.Resources.List.params ->
    (Request.Resources.List.result, string) result;
  on_resources_read :
    Request.Resources.Read.params ->
    (Request.Resources.Read.result, string) result;
  on_resources_subscribe :
    Request.Resources.Subscribe.params ->
    (Request.Resources.Subscribe.result, string) result;
  on_resources_unsubscribe :
    Request.Resources.Unsubscribe.params ->
    (Request.Resources.Unsubscribe.result, string) result;
  on_resources_templates_list :
    Request.Resources.Templates.List.params ->
    (Request.Resources.Templates.List.result, string) result;
  on_prompts_list :
    Request.Prompts.List.params -> (Request.Prompts.List.result, string) result;
  on_prompts_get :
    Request.Prompts.Get.params -> (Request.Prompts.Get.result, string) result;
  on_tools_list :
    Request.Tools.List.params -> (Request.Tools.List.result, string) result;
  on_tools_call :
    Request.Tools.Call.params -> (Request.Tools.Call.result, string) result;
  on_sampling_create_message :
    Request.Sampling.CreateMessage.params ->
    (Request.Sampling.CreateMessage.result, string) result;
  on_elicitation_create :
    Request.Elicitation.Create.params ->
    (Request.Elicitation.Create.result, string) result;
  on_logging_set_level :
    Request.Logging.SetLevel.params ->
    (Request.Logging.SetLevel.result, string) result;
  on_completion_complete :
    Request.Completion.Complete.params ->
    (Request.Completion.Complete.result, string) result;
  on_roots_list :
    Request.Roots.List.params -> (Request.Roots.List.result, string) result;
  on_ping : Request.Ping.params -> (Request.Ping.result, string) result;
}

type notification_handler = {
  on_initialized : Notification.Initialized.params -> unit;
  on_progress : Notification.Progress.params -> unit;
  on_cancelled : Notification.Cancelled.params -> unit;
  on_roots_list_changed : Notification.Roots.ListChanged.params -> unit;
}

type t = {
  handler : handler;
  notification_handler : notification_handler;
  mutable initialized : bool;
  mutable client_capabilities : Capabilities.client option;
  server_info : ServerInfo.t;
  server_capabilities : Capabilities.server;
}

let create ~handler ~notification_handler ~server_info ~server_capabilities =
  {
    handler;
    notification_handler;
    initialized = false;
    client_capabilities = None;
    server_info;
    server_capabilities;
  }

let handle_request (server : t) (id : Jsonrpc.Id.t) (request : Request.t) :
    outgoing_message =
  (* Extract and validate the meta field from the request *)
  let meta_to_validate =
    match request with
    | Request.Initialize _ -> None (* Initialize has no meta in params *)
    | Request.ResourcesList params -> params.meta
    | Request.ResourcesRead params -> params.meta
    | Request.ResourcesSubscribe params -> params.meta
    | Request.ResourcesUnsubscribe params -> params.meta
    | Request.ResourcesTemplatesList params -> params.meta
    | Request.PromptsList params -> params.meta
    | Request.PromptsGet params -> params.meta
    | Request.ToolsList params -> params.meta
    | Request.ToolsCall params -> params.meta
    | Request.SamplingCreateMessage params -> params.metadata
    | Request.ElicitationCreate params -> params.meta
    | Request.LoggingSetLevel params -> params.meta
    | Request.CompletionComplete params -> params.meta
    | Request.RootsList params -> params.meta
    | Request.Ping params -> params.meta
  in
  match Meta.validate meta_to_validate with
  | Error msg ->
      error_to_outgoing ~id ~code:ErrorCode.invalid_params
        ~message:("Invalid _meta: " ^ msg) ()
  | Ok () -> (
      (* Proceed with normal request handling *)
      match request with
      | Request.Initialize params ->
          if server.initialized then
            error_to_outgoing ~id ~code:ErrorCode.invalid_request
              ~message:"Server already initialized" ()
          else (
            server.client_capabilities <- Some params.capabilities;
            match server.handler.on_initialize params with
            | Ok custom_result ->
                server.initialized <- true;
                (* Merge custom result with defaults, ensuring protocol version and capabilities are preserved *)
                let merged_result =
                  {
                    custom_result with
                    Request.Initialize.protocol_version =
                      params.protocol_version;
                    capabilities = server.server_capabilities;
                    server_info = server.server_info;
                  }
                in
                response_to_outgoing ~id (Request.Initialize merged_result)
            | Error msg ->
                error_to_outgoing ~id ~code:ErrorCode.internal_error
                  ~message:msg ())
      | Request.ResourcesList params -> (
          match server.handler.on_resources_list params with
          | Ok result -> response_to_outgoing ~id (Request.ResourcesList result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ResourcesRead params -> (
          match server.handler.on_resources_read params with
          | Ok result -> response_to_outgoing ~id (Request.ResourcesRead result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ResourcesSubscribe params -> (
          match server.handler.on_resources_subscribe params with
          | Ok result ->
              response_to_outgoing ~id (Request.ResourcesSubscribe result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ResourcesUnsubscribe params -> (
          match server.handler.on_resources_unsubscribe params with
          | Ok result ->
              response_to_outgoing ~id (Request.ResourcesUnsubscribe result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ResourcesTemplatesList params -> (
          match server.handler.on_resources_templates_list params with
          | Ok result ->
              response_to_outgoing ~id (Request.ResourcesTemplatesList result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.PromptsList params -> (
          match server.handler.on_prompts_list params with
          | Ok result -> response_to_outgoing ~id (Request.PromptsList result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.PromptsGet params -> (
          match server.handler.on_prompts_get params with
          | Ok result -> response_to_outgoing ~id (Request.PromptsGet result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ToolsList params -> (
          match server.handler.on_tools_list params with
          | Ok result -> response_to_outgoing ~id (Request.ToolsList result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ToolsCall params -> (
          match server.handler.on_tools_call params with
          | Ok result -> response_to_outgoing ~id (Request.ToolsCall result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.SamplingCreateMessage params -> (
          match server.handler.on_sampling_create_message params with
          | Ok result ->
              response_to_outgoing ~id (Request.SamplingCreateMessage result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.ElicitationCreate params -> (
          match server.handler.on_elicitation_create params with
          | Ok result ->
              response_to_outgoing ~id (Request.ElicitationCreate result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.LoggingSetLevel params -> (
          match server.handler.on_logging_set_level params with
          | Ok result ->
              response_to_outgoing ~id (Request.LoggingSetLevel result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.CompletionComplete params -> (
          match server.handler.on_completion_complete params with
          | Ok result ->
              response_to_outgoing ~id (Request.CompletionComplete result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.RootsList params -> (
          match server.handler.on_roots_list params with
          | Ok result -> response_to_outgoing ~id (Request.RootsList result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ())
      | Request.Ping params -> (
          match server.handler.on_ping params with
          | Ok result -> response_to_outgoing ~id (Request.Ping result)
          | Error msg ->
              error_to_outgoing ~id ~code:ErrorCode.internal_error ~message:msg
                ()))

let handle_notification (server : t) (notification : Notification.t) : unit =
  (* Extract and validate the meta field from the notification *)
  let meta_to_validate =
    match notification with
    | Notification.Initialized params -> params.meta
    | Notification.Progress _params -> None (* Progress doesn't have meta *)
    | Notification.Cancelled _params -> None (* Cancelled doesn't have meta *)
    | Notification.RootsListChanged params -> params.meta
    | _ -> None
  in
  match Meta.validate meta_to_validate with
  | Error msg ->
      (* Log error, but don't crash since notifications are fire-and-forget *)
      Logs.err (fun m -> m "Invalid meta in notification: %s" msg)
  | Ok () -> (
      (* Proceed with normal notification handling *)
      match notification with
      | Notification.Initialized params ->
          server.notification_handler.on_initialized params
      | Notification.Progress params ->
          server.notification_handler.on_progress params
      | Notification.Cancelled params ->
          server.notification_handler.on_cancelled params
      | Notification.RootsListChanged params ->
          server.notification_handler.on_roots_list_changed params
      | _ -> () (* Server doesn't handle other notifications *))

let rec handle_message (server : t) (msg : incoming_message) :
    outgoing_message option =
  match msg with
  | Request (id, request) ->
      if
        (not server.initialized)
        && not (match request with Request.Initialize _ -> true | _ -> false)
      then
        Some
          (error_to_outgoing ~id ~code:ErrorCode.invalid_request
             ~message:"Server not initialized" ())
      else Some (handle_request server id request)
  | Notification notification ->
      handle_notification server notification;
      None
  | Response _ -> None (* Server doesn't handle responses *)
  | Batch_request requests ->
      (* Process each request in the batch and collect responses *)
      let responses =
        List.filter_map (fun req -> handle_message server req) requests
      in
      if responses = [] then None else Some (Batch_response responses)
  | Batch_response _ -> None (* Server ignores incoming batch responses *)

let send_notification (_server : t) (notification : Notification.t) :
    outgoing_message =
  notification_to_outgoing notification

let is_initialized (server : t) : bool = server.initialized

let get_client_capabilities (server : t) : Capabilities.client option =
  server.client_capabilities

let default_handler : handler =
  {
    on_initialize =
      (fun _params ->
        Ok
          {
            Request.Initialize.protocol_version =
              Protocol.default_negotiated_version;
            capabilities =
              {
                experimental = None;
                logging = None;
                completions = None;
                prompts = None;
                resources = None;
                tools = None;
              };
            server_info = { name = "default-server"; version = "1.0.0" };
            instructions = None;
            meta = None;
          });
    on_resources_list =
      (fun params ->
        (* Echo the metadata back in the response *)
        Ok
          {
            Request.Resources.List.resources = [];
            next_cursor = None;
            meta = params.meta;
          });
    on_resources_read =
      (fun params ->
        Ok { Request.Resources.Read.contents = []; meta = params.meta });
    on_resources_subscribe = (fun _ -> Ok ());
    on_resources_unsubscribe = (fun _ -> Ok ());
    on_resources_templates_list =
      (fun params ->
        Ok
          {
            Request.Resources.Templates.List.resource_templates = [];
            next_cursor = None;
            meta = params.meta;
          });
    on_prompts_list =
      (fun params ->
        Ok
          {
            Request.Prompts.List.prompts = [];
            next_cursor = None;
            meta = params.meta;
          });
    on_prompts_get =
      (fun params ->
        Ok
          {
            Request.Prompts.Get.description = None;
            messages = [];
            meta = params.meta;
          });
    on_tools_list =
      (fun params ->
        Ok
          {
            Request.Tools.List.tools = [];
            next_cursor = None;
            meta = params.meta;
          });
    on_tools_call =
      (fun params ->
        Ok
          {
            Request.Tools.Call.content = [];
            is_error = None;
            structured_content = None;
            meta = params.meta;
          });
    on_sampling_create_message = (fun _ -> Error "Not implemented");
    on_elicitation_create = (fun _ -> Error "Not implemented");
    on_logging_set_level = (fun params -> Ok { meta = params.meta });
    on_completion_complete = (fun _ -> Error "Not implemented");
    on_roots_list =
      (fun params -> Ok { Request.Roots.List.roots = []; meta = params.meta });
    on_ping = (fun params -> Ok { meta = params.meta });
  }

let default_notification_handler : notification_handler =
  {
    on_initialized = (fun _ -> ());
    on_progress = (fun _ -> ());
    on_cancelled = (fun _ -> ());
    on_roots_list_changed = (fun _ -> ());
  }
