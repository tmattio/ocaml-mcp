# JSON codecs

The protocol and SDK use `Jsont.t` codecs and `Jsont.json` values. This changes the
OCaml source API; JSON member names, method names, and protocol payload shapes stay
the same, with the numeric acceptance and formatting differences described below.

## Protocol types

Use the codec supplied by each protocol module instead of generated Yojson
functions:

```ocaml
let decode_tool json = Jsont.Json.decode Mcp.Types.Tool.json json
let encode_tool tool = Jsont.Json.encode Mcp.Types.Tool.json tool

let decode_tool_result json =
  Jsont.Json.decode Mcp.Request.Tools.Call.result_json json
```

Record modules expose `json`; named types expose `<name>_json`. Request modules
expose `params_json` and `result_json`. Metadata, schemas, arguments, structured
tool content, and other generic payloads are `Jsont.json` values.

`Jsont.Json.decode` and `Jsont.Json.encode` return a result with a descriptive
error. `Mcp.Json.of_string` and `Mcp.Json.to_string` provide convenience functions
for generic values and raise `Invalid_argument` for invalid input. Construct
generic objects with `Mcp.Json.object_` or the constructors in `Jsont.Json`.

## SDK argument converters

`Mcp_sdk.Json_converter` and `Mcp_sdk_eio.Json_converter` now require one
bidirectional codec and a JSON Schema:

```ocaml
module Args = struct
  type t = { city : string }

  let json =
    Jsont.Object.map (fun city -> { city })
    |> Jsont.Object.mem "city" Jsont.string ~enc:(fun args -> args.city)
    |> Jsont.Object.finish

  let schema () =
    Mcp.Json.of_string
      {|{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}|}
end

let register server =
  Mcp_sdk.Server.tool server "weather" ~args:(module Args)
    (fun args _ctx -> Ok (Mcp_sdk.Tool_result.text args.city))
```

Replace `to_yojson` and `of_yojson` members with `json`. The schema remains explicit;
the codec does not generate it. Tool input schemas are validated before decoding
arguments. Structured tool output is validated against its output schema after
the handler returns. Synchronous and Eio Promise handlers use the same validation
paths. Tools without arguments still validate structured output when an output
schema is provided.

## SDK client builders

`tools_call` and `prompts_get` accept `~args_json`, a codec for the argument value.
Both return `(outgoing_message, string) result` so an encoding failure can be
handled before sending a request:

```ocaml
let prepare_weather client callback =
  Mcp_sdk.Client.tools_call client ~name:"weather"
    ~args:{ Args.city = "London" } ~args_json:Args.json callback
```

The callback handles the eventual server response. It is not called when the
builder returns an encoding error. Prompt arguments must encode to an object;
string members stay strings and other members are serialized as JSON text to
meet the protocol's string-valued prompt argument format. This uses native Jsont
formatting: a JSON number written as `2.0` can become the argument string `"2"`,
and `0.1` can become `"0.10000000000000001"`. Pass string values when the exact
argument text must be preserved.

## Numbers and dependency boundaries

`Jsont.json` represents JSON numbers as floating-point values. Integer identifiers,
tokens, and integer-valued protocol fields must be exactly representable in the
interoperable range `[-9007199254740991, 9007199254740991]`. The native codecs
accept integral floating-point values, including those decoded from `1.0` or
`1e0`, and reject values outside that range. An already decoded `Jsont.json`
number has floating-point precision; its original token cannot be recovered.

`Mcp.Json.of_string` additionally checks number tokens before conversion. It
rejects integer literals outside the safe range and fractional or exponent tokens
whose rounding would change their value to an integer, such as
`9007199254740990.5` or `1e-9999`. Nonfinite numbers are rejected. Other generic
fractional numbers retain floating-point precision. String identifiers remain
strings, including numeric strings.

Yojson remains a dependency of `jsonrpc` and `jsonschema`. Conversion to their
representations is confined to the JSON-RPC boundary and the JSON Schema validator
adapter. Schema validation still uses `jsonschema`, including arbitrary schema
keywords supported by that library. Protocol types and SDK converters no longer
use `ppx_deriving_yojson`; this does not remove Yojson or JSON PPX dependencies
from third-party packages.
