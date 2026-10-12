(** Weather MCP Server using the SDK *)

open Mcp_sdk

(* Define the argument type for get-weather tool *)
type weather_args = { city : string }

let weather_args_json =
  Jsont.Object.map (fun city -> { city })
  |> Jsont.Object.mem "city" Jsont.string ~enc:(fun args -> args.city)
  |> Jsont.Object.finish

(* Simulated weather data *)
let get_weather city =
  Random.self_init ();
  let temp = 15 + Random.int 20 in
  let conditions = [| "sunny"; "cloudy"; "rainy"; "partly cloudy" |] in
  let condition = conditions.(Random.int (Array.length conditions)) in
  Printf.sprintf "Weather in %s: %d°C, %s" city temp condition

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  (* Create server using SDK *)
  let server =
    Server.create
      ~server_info:{ name = "SDK Weather Server"; version = "1.0.0" }
      ()
  in

  (* Register the get-weather tool with type-safe arguments *)
  Server.tool server "get-weather" ~title:"Get Weather"
    ~description:"Get current weather for a city"
    ~args:
      (module struct
        type t = weather_args

        let json = weather_args_json

        let schema () =
          Mcp.Json.object_
            [
              ("type", Jsont.Json.string "object");
              ( "properties",
                Mcp.Json.object_
                  [
                    ( "city",
                      Mcp.Json.object_ [ ("type", Jsont.Json.string "string") ]
                    );
                  ] );
              ("required", Jsont.Json.list [ Jsont.Json.string "city" ]);
            ]
      end)
    (fun args _ctx ->
      Ok
        {
          Mcp.Request.Tools.Call.content =
            [
              Mcp.Types.Content.Text
                { type_ = "text"; text = get_weather args.city; meta = None };
            ];
          is_error = None;
          structured_content = None;
          meta = None;
        });

  (* Use stdio transport *)
  let stdin = Eio.Stdenv.stdin env in
  let stdout = Eio.Stdenv.stdout env in
  let transport = Mcp_eio.Stdio.create ~stdin ~stdout in
  let clock = Eio.Stdenv.clock env in
  let connection =
    Mcp_eio.Connection.create ~clock (module Mcp_eio.Stdio) transport
  in

  (* Convert SDK server to MCP server and run *)
  let mcp_server = Server.to_mcp_server server in
  Mcp_eio.Connection.serve ~sw connection mcp_server
