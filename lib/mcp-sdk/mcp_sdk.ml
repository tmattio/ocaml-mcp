module Types = Mcp.Types
module Protocol = Mcp.Protocol

(* Re-export common modules *)
module Context = Common.Context
module Tool_result = Common.Tool_result
module Logging = Common.Logging

(* Setup logging *)
let src = Logs.Src.create "mcp.sdk" ~doc:"MCP SDK logging"

module Log = (val Logs.src_log src : Logs.LOG)

module type Json_converter = Common.Json_converter
module type Io = Common.Io

module Make_server (Io : Io) = struct
  include Common.Make (Io)
end

module Server = struct
  (* Define the synchronous Identity monad *)
  module Io = struct
    type 'a t = 'a

    let return x = x
    let map f x = f x
    let run x = x
  end

  (* Instantiate the functor with the Identity monad *)
  include Common.Make (Io)
end

module Client = struct
  type t = {
    client_info : Types.ClientInfo.t;
    client_capabilities : Types.Capabilities.client;
  }

  let create ~client_info ~client_capabilities =
    { client_info; client_capabilities }

  let get_mcp_client t =
    Mcp.Client.create
      ~notification_handler:Mcp.Client.default_notification_handler
      ~client_info:t.client_info ~client_capabilities:t.client_capabilities ()

  let initialize t callback =
    let mcp_client = get_mcp_client t in
    Mcp.Client.initialize mcp_client
      ~protocol_version:Types.Protocol.latest_version (function
      | Ok result -> callback (Ok result)
      | Error e -> callback (Error e))

  let tools_list t ?meta callback =
    let params : Mcp.Request.Tools.List.params = { cursor = None; meta } in
    let request : Mcp.Request.t = Mcp.Request.ToolsList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Jsont.Json.decode Mcp.Request.Tools.List.result_json json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let tools_call t ~name ~args ~args_json ?meta callback =
    match Jsont.Json.encode args_json args with
    | Error error -> Error ("Failed to encode arguments: " ^ error)
    | Ok arguments ->
        let params : Mcp.Request.Tools.Call.params =
          { name; arguments = Some arguments; meta }
        in
        let request : Mcp.Request.t = Mcp.Request.ToolsCall params in
        Ok
          (Mcp.Client.send_request (get_mcp_client t) request (function
            | Ok json -> (
                match
                  Jsont.Json.decode Mcp.Request.Tools.Call.result_json json
                with
                | Ok result -> callback (Ok result)
                | Error e -> callback (Error e))
            | Error e -> callback (Error e.message)))

  let resources_list t ?meta callback =
    let params = { Mcp.Request.Resources.List.cursor = None; meta } in
    let request : Mcp.Request.t = Mcp.Request.ResourcesList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match
            Jsont.Json.decode Mcp.Request.Resources.List.result_json json
          with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let resources_read t ~uri ?meta callback =
    let params = { Mcp.Request.Resources.Read.uri; meta } in
    let request : Mcp.Request.t = Mcp.Request.ResourcesRead params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match
            Jsont.Json.decode Mcp.Request.Resources.Read.result_json json
          with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let prompts_list t ?meta callback =
    let params = { Mcp.Request.Prompts.List.cursor = None; meta } in
    let request : Mcp.Request.t = Mcp.Request.PromptsList params in
    Mcp.Client.send_request (get_mcp_client t) request (function
      | Ok json -> (
          match Jsont.Json.decode Mcp.Request.Prompts.List.result_json json with
          | Ok result -> callback (Ok result)
          | Error e -> callback (Error e))
      | Error e -> callback (Error e.message))

  let prompts_get t ~name ~args ~args_json ?meta callback =
    match Jsont.Json.encode args_json args with
    | Error error -> Error ("Failed to encode arguments: " ^ error)
    | Ok json -> (
        match Mcp.Json.fields json with
        | None -> Error "Prompt arguments must encode to a JSON object"
        | Some fields ->
            let arguments =
              Some
                (List.map
                   (fun (key, value) ->
                     let text =
                       match Mcp.Json.get_string value with
                       | Some text -> text
                       | None -> Mcp.Json.to_string value
                     in
                     (key, text))
                   fields)
            in
            let params = { Mcp.Request.Prompts.Get.name; arguments; meta } in
            let request : Mcp.Request.t = Mcp.Request.PromptsGet params in
            Ok
              (Mcp.Client.send_request (get_mcp_client t) request (function
                | Ok json -> (
                    match
                      Jsont.Json.decode Mcp.Request.Prompts.Get.result_json json
                    with
                    | Ok result -> callback (Ok result)
                    | Error e -> callback (Error e))
                | Error e -> callback (Error e.message))))
end
