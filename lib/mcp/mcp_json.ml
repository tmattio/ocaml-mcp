type t = Jsont.json
(** Native JSON helpers and explicit adapters for JSON-RPC and JSON Schema. *)

let null = Jsont.Json.null ()
let string value = Jsont.Json.string value
let bool value = Jsont.Json.bool value
let array values = Jsont.Json.list values

let object_ fields =
  Jsont.Json.object'
    (List.map (fun (key, value) -> ((key, Jsont.Meta.none), value)) fields)

let fields = function
  | Jsont.Object (members, _) ->
      Some (List.map (fun ((key, _), value) -> (key, value)) members)
  | _ -> None

let get_string = function Jsont.String (value, _) -> Some value | _ -> None
let get_array = function Jsont.Array (value, _) -> Some value | _ -> None
let member name value = Option.bind (fields value) (List.assoc_opt name)

let number value =
  if Float.is_finite value then Jsont.Json.number value
  else invalid_arg "Nonfinite JSON number"

let int value =
  let value64 = Int64.of_int value in
  if Int64.abs value64 > 9007199254740991L then
    invalid_arg "JSON integer exceeds the interoperable numeric range";
  number (float_of_int value)

let rec of_yojson : Yojson.Safe.t -> t = function
  | `Null -> null
  | `Bool value -> bool value
  | `String value -> string value
  | `Int value -> int value
  | `Float value -> number value
  | `Intlit value -> (
      match Int64.of_string_opt value with
      | Some value
        when value >= -9007199254740991L && value <= 9007199254740991L ->
          number (Int64.to_float value)
      | _ ->
          invalid_arg
            "JSON integer literal exceeds the interoperable numeric range")
  | `List values | `Tuple values -> array (List.map of_yojson values)
  | `Assoc values ->
      object_ (List.map (fun (key, value) -> (key, of_yojson value)) values)
  | `Variant (name, None) -> object_ [ ("variant", string name) ]
  | `Variant (name, Some value) ->
      object_ [ ("variant", string name); ("value", of_yojson value) ]

let rec to_basic : t -> Yojson.Basic.t = function
  | Jsont.Null _ -> `Null
  | Jsont.Bool (value, _) -> `Bool value
  | Jsont.String (value, _) -> `String value
  | Jsont.Number (value, _) ->
      if not (Float.is_finite value) then invalid_arg "Nonfinite JSON number";
      if
        Float.is_integer value
        && abs_float value <= 9007199254740991.
        && value >= float_of_int min_int
        && value < float_of_int max_int
      then `Int (int_of_float value)
      else `Float value
  | Jsont.Array (values, _) -> `List (List.map to_basic values)
  | Jsont.Object (values, _) ->
      `Assoc (List.map (fun ((key, _), value) -> (key, to_basic value)) values)

let rec basic_to_safe : Yojson.Basic.t -> Yojson.Safe.t = function
  | `Null -> `Null
  | `Bool v -> `Bool v
  | `String v -> `String v
  | `Int v -> `Int v
  | `Float v -> `Float v
  | `List values -> `List (List.map basic_to_safe values)
  | `Assoc values ->
      `Assoc (List.map (fun (key, value) -> (key, basic_to_safe value)) values)

let to_yojson value = basic_to_safe (to_basic value)
let of_basic value = of_yojson (basic_to_safe value)

let rec validate_numbers = function
  | Jsont.Number (value, _) when not (Float.is_finite value) ->
      invalid_arg "Nonfinite JSON number"
  | Jsont.Array (values, _) -> List.iter validate_numbers values
  | Jsont.Object (values, _) ->
      List.iter (fun (_, value) -> validate_numbers value) values
  | _ -> ()

let to_string value =
  validate_numbers value;
  match Jsont_bytesrw.encode_string Jsont.json value with
  | Ok text -> text
  | Error _ -> invalid_arg "Could not encode JSON"

(* Is a decimal token mathematically integral, before float rounding? *)
let decimal_is_integral token =
  let length = String.length token in
  let exponent_at =
    match String.index_opt token 'e' with
    | Some index -> index
    | None -> Option.value (String.index_opt token 'E') ~default:length
  in
  let coefficient = String.sub token 0 exponent_at in
  let fractional_digits =
    match String.index_opt coefficient '.' with
    | None -> 0
    | Some index -> String.length coefficient - index - 1
  in
  let digits =
    String.to_seq coefficient
    |> Seq.filter (fun c -> c >= '0' && c <= '9')
    |> String.of_seq
  in
  let rec trailing_zeros index =
    if index < 0 then String.length digits
    else if digits.[index] = '0' then trailing_zeros (index - 1)
    else String.length digits - index - 1
  in
  let zeros = trailing_zeros (String.length digits - 1) in
  if zeros = String.length digits then true
  else
    let exponent =
      if exponent_at = length then Some 0
      else
        int_of_string_opt
          (String.sub token (exponent_at + 1) (length - exponent_at - 1))
    in
    match exponent with
    | Some exponent -> exponent >= fractional_digits - zeros
    | None -> false

(* Check integer tokens before the float-based generic decoder sees them.
   String contents, including escaped quotes, are never interpreted as numbers. *)
let check_integer_tokens text =
  let length = String.length text in
  let rec scan index in_string escaped =
    if index >= length then ()
    else
      let character = text.[index] in
      if in_string then
        if escaped then scan (index + 1) true false
        else if character = '\\' then scan (index + 1) true true
        else scan (index + 1) (character <> '"') false
      else if character = '"' then scan (index + 1) true false
      else if character = '-' || (character >= '0' && character <= '9') then begin
        let stop = ref (index + 1) in
        while
          !stop < length
          &&
          match text.[!stop] with
          | '0' .. '9' | '.' | 'e' | 'E' | '+' | '-' -> true
          | _ -> false
        do
          incr stop
        done;
        let token = String.sub text index (!stop - index) in
        (if
           not
             (String.contains token '.' || String.contains token 'e'
            || String.contains token 'E')
         then
           match Int64.of_string_opt token with
           | Some value
             when value >= -9007199254740991L && value <= 9007199254740991L ->
               ()
           | _ ->
               invalid_arg
                 "JSON integer exceeds the interoperable numeric range"
         else
           match float_of_string_opt token with
           | Some value
             when Float.is_finite value && Float.is_integer value
                  && not (decimal_is_integral token) ->
               invalid_arg "JSON fractional number would round to an integer"
           | _ -> ());
        scan !stop false false
      end
      else scan (index + 1) false false
  in
  scan 0 false false

let of_string text =
  check_integer_tokens text;
  match Jsont_bytesrw.decode_string Jsont.json text with
  | Ok value ->
      validate_numbers value;
      value
  | Error _ -> invalid_arg "Invalid JSON"

(* The jsonrpc dependency retains its own Yojson-shaped representation. *)
let of_jsonrpc value = of_yojson (value : Jsonrpc.Json.t :> Yojson.Safe.t)
let to_jsonrpc value = (to_yojson value :> Jsonrpc.Json.t)
