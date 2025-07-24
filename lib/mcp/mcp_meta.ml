(** Validator for MCP _meta field keys. *)

let label_re = Re.Perl.compile_pat "^[a-z]([-a-z0-9]*[a-z0-9])?$"

let name_re =
  Re.compile
    (Re.seq
       [
         Re.bos;
         Re.alt [ Re.rg 'a' 'z'; Re.rg 'A' 'Z'; Re.rg '0' '9' ];
         Re.opt
           (Re.seq
              [
                Re.rep1
                  (Re.alt
                     [
                       Re.char '-';
                       Re.char '_';
                       Re.char '.';
                       Re.rg 'a' 'z';
                       Re.rg 'A' 'Z';
                       Re.rg '0' '9';
                     ]);
                Re.alt [ Re.rg 'a' 'z'; Re.rg 'A' 'Z'; Re.rg '0' '9' ];
              ]);
         Re.eos;
       ])

let mcp_reserved_prefix_re =
  Re.compile
    (Re.seq
       [
         Re.rep Re.any;
         Re.alt [ Re.str "modelcontextprotocol"; Re.str "mcp" ];
         Re.char '.';
         Re.rep Re.any;
         Re.char '/';
       ])

let is_valid_label s = Re.execp label_re s
let is_valid_name s = s = "" || Re.execp name_re s
let is_mcp_reserved_prefix s = Re.execp mcp_reserved_prefix_re s

let validate_key key =
  match String.split_on_char '/' key with
  | [ name ] ->
      if is_valid_name name then Ok ()
      else Error (Printf.sprintf "Invalid _meta key name: '%s'" key)
  | [ prefix_part; name ] ->
      if not (is_valid_name name) then
        Error (Printf.sprintf "Invalid _meta key name segment: '%s'" name)
      else if is_mcp_reserved_prefix (key ^ "/") then
        Error
          (Printf.sprintf "Using a reserved MCP prefix is not allowed: '%s'" key)
      else
        let labels = String.split_on_char '.' prefix_part in
        if List.for_all is_valid_label labels then Ok ()
        else Error (Printf.sprintf "Invalid _meta key prefix: '%s'" prefix_part)
  | _ -> Error (Printf.sprintf "Invalid _meta key format: '%s'" key)

let rec validate_json (json : Yojson.Safe.t) : (unit, string) result =
  match json with
  | `Assoc items ->
      List.fold_left
        (fun acc (key, value) ->
          match acc with
          | Error _ -> acc
          | Ok () -> (
              match validate_key key with
              | Error e -> Error e
              | Ok () -> validate_json value))
        (Ok ()) items
  | `List items ->
      List.fold_left
        (fun acc value ->
          match acc with Error _ -> acc | Ok () -> validate_json value)
        (Ok ()) items
  | `Bool _ | `Float _ | `Int _ | `Intlit _ | `String _ | `Null -> Ok ()
  | `Tuple _ | `Variant _ ->
      Error "Tuples and variants are not supported in _meta"

let validate (meta_option : Yojson.Safe.t option) : (unit, string) result =
  match meta_option with None -> Ok () | Some json -> validate_json json
