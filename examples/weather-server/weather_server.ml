(** Weather MCP Server using the SDK *)

open Mcp_sdk

(* Define the argument type for get-weather tool *)
type weather_args = { city : string } [@@deriving yojson]

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

        let to_yojson = weather_args_to_yojson
        let of_yojson = weather_args_of_yojson

        let schema () =
          `Assoc
            [
              ("type", `String "object");
              ( "properties",
                `Assoc [ ("city", `Assoc [ ("type", `String "string") ]) ] );
              ("required", `List [ `String "city" ]);
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
  let connection = Mcp_eio.Connection.create (module Mcp_eio.Stdio) transport in

  (* Convert SDK server to MCP server and run *)
  let mcp_server = Server.to_mcp_server server in
  Mcp_eio.Connection.serve ~sw connection mcp_server
