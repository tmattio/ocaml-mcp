open Mcp_sdk_eio

(* Example async weather server using mcp-sdk-eio *)

let get_weather_async ~sw:_ ~env ~location =
  (* Simulate async network call *)
  Eio.traceln "Fetching weather for %s..." location;
  Eio.Fiber.yield ();
  Eio.Time.sleep (Eio.Stdenv.clock env) 0.1;

  (* Return mock weather data *)
  match String.lowercase_ascii location with
  | "san francisco" | "sf" -> Ok (68, "partly cloudy")
  | "new york" | "nyc" -> Ok (75, "sunny")
  | "london" -> Ok (55, "rainy")
  | "tokyo" -> Ok (72, "clear")
  | _ -> Error (Printf.sprintf "Unknown location: %s" location)

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  (* Create async server *)
  let server =
    Server.create
      ~server_info:{ name = "async-weather-server"; version = "0.1.0" }
      ()
  in

  (* Register async tool that fetches weather *)
  Server.tool server "get-weather" ~title:"Get Weather"
    ~description:"Get current weather for a location"
    ~args:
      (module struct
        type t = string

        let to_yojson s = `String s

        let of_yojson = function
          | `String s -> Ok s
          | _ -> Error "Expected string"

        let schema () =
          `Assoc
            [
              ("type", `String "string");
              ("description", `String "Location name");
            ]
      end)
    (fun location ctx ->
      (* Report progress asynchronously *)
      Context.report_progress_async ctx ~sw ~progress:0.0 ~total:100.0 ();

      (* Perform async weather fetch *)
      let promise, resolver = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          match get_weather_async ~sw ~env ~location with
          | Ok (temp, conditions) ->
              Context.report_progress_async ctx ~sw ~progress:100.0 ~total:100.0
                ();
              Eio.Promise.resolve resolver
                (Ok
                   (Mcp_sdk.Tool_result.text
                      (Printf.sprintf "Weather in %s: %d°F, %s" location temp
                         conditions)))
          | Error msg -> Eio.Promise.resolve resolver (Error msg));
      promise);

  (* Register async resource that provides weather data *)
  Server.resource server "weather-data" ~uri:"weather://current"
    ~description:"Current weather data" (fun _uri ctx ->
      (* Simulate async data fetching *)
      let promise, resolver = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Time.sleep (Eio.Stdenv.clock env) 0.05;
          Eio.Promise.resolve resolver
            (Ok
               {
                 Mcp.Request.Resources.Read.contents =
                   [
                     {
                       Mcp.Types.Content.uri = "weather://current";
                       mime_type = Some "text/plain";
                       text =
                         Some
                           "Current weather data:\n\
                            - SF: 68°F\n\
                            - NYC: 75°F\n\
                            - London: 55°F";
                       blob = None;
                       meta = None;
                     };
                   ];
                 meta = Context.meta ctx;
               }));
      promise);

  (* Register async prompt *)
  Server.prompt server "weather-report" ~title:"Weather Report"
    ~description:"Generate a weather report for multiple cities" (fun () _ctx ->
      async_ok
        {
          Mcp.Request.Prompts.Get.description =
            Some "This prompt generates a weather report for major cities";
          messages =
            [
              {
                Mcp.Types.Prompt.role = "user";
                content =
                  Mcp.Types.Content.Text
                    {
                      type_ = "text";
                      text =
                        "Please provide a weather report for San Francisco, \
                         New York, and London.";
                      meta = None;
                    };
              };
            ];
          meta = None;
        });

  (* Set up connection *)
  let stdin = Eio.Stdenv.stdin env in
  let stdout = Eio.Stdenv.stdout env in
  let transport = Mcp_eio.Stdio.create ~stdin ~stdout in
  let clock = Eio.Stdenv.clock env in
  let connection =
    Mcp_eio.Connection.create ~clock (module Mcp_eio.Stdio) transport
  in

  (* Run the async server *)
  Eio.traceln "Starting async weather server...";
  Server.run ~sw ~env server connection
