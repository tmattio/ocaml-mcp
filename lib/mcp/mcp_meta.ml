(** Validator for MCP _meta field keys. *)

(* SPEC: "Labels MUST start with a letter and end with a letter or digit; interior characters can be letters, digits, or hyphens (-)." *)
let is_valid_label s =
  let label_re = Re.Perl.compile_pat "^[a-zA-Z]([-a-zA-Z0-9]*[a-zA-Z0-9])?$" in
  Re.execp label_re s

(* SPEC: "If specified, MUST be a series of labels separated by dots (.), followed by a slash (/)." *)
let prefix_labels str =
  let label_strs = String.split_on_char '.' str in
  List.fold_right
    (fun h acc ->
      (* If the label is valid, accumulate it; otherwise, return an error. *)
      Result.bind acc (fun acc ->
          if is_valid_label h then Ok (h :: acc)
          else Error (Printf.sprintf "Invalid label: '%s' in prefix: %s" h str)))
    label_strs (Ok [])

(* SPEC: "Any prefix beginning with zero or more valid labels, followed by modelcontextprotocol or mcp, followed by any valid label, is reserved for MCP use." *)
let is_reserved_prefix labels =
  let len = List.length labels in
  if len < 2 then false
  else
    let reserved_keys = [ "modelcontextprotocol"; "mcp" ] in
    (* essentially, the spec says that [ ... , reserved_label , ANY ] is reserved *)
    let check_key = List.nth labels (len - 2) in
    List.mem check_key reserved_keys

(* SPEC: "Unless empty, MUST begin and end with an alphanumeric character ([a-z0-9A-Z]).
MAY contain hyphens (-), underscores (_), dots (.), and alphanumerics in between." *)
let is_valid_name s =
  let name_re =
    Re.Perl.compile_pat "^[a-zA-Z0-9]([-_.a-zA-Z0-9]*[a-zA-Z0-9])?$"
  in
  s = "" || Re.execp name_re s

(* SPEC: "Key name format: valid _meta key names have two segments: an optional prefix, and a name.
If specified, MUST be a series of labels separated by dots (.), followed by a slash (/)."
*)
let validate_key key =
  match String.split_on_char '/' key with
  | [ name ] ->
      if is_valid_name name then Ok ()
      else Error (Printf.sprintf "Invalid _meta key name: '%s'" key)
  | [ prefix_part; name ] ->
      if not (is_valid_name name) then
        Error (Printf.sprintf "Invalid _meta key name segment: '%s'" name)
      else
        Result.bind (prefix_labels prefix_part) (fun labels ->
            if is_reserved_prefix labels then
              Error
                (Printf.sprintf
                   "Using a reserved MCP prefix is not allowed: '%s'" key)
            else Ok ())
  | _ -> Error (Printf.sprintf "Invalid _meta key format: '%s'" key)

(* SPEC: "The _meta property/parameter is reserved by MCP to allow clients and servers to attach additional metadata to their interactions.
Certain key names are reserved by MCP for protocol-level metadata, as specified below; implementations MUST NOT make assumptions about values at these keys.
Additionally, definitions in the schema may reserve particular names for purpose-specific metadata, as declared in those definitions.
Key name format: valid _meta key names have two segments: an optional prefix, and a name."
*)
let validate_meta_json (json : Yojson.Safe.t) : (unit, string) result =
  (* All keys must be valid _meta.<key> *)
  match json with
  | `Assoc items ->
      List.fold_left
        (fun acc (key, _) -> Result.bind acc (fun _ -> validate_key key))
        (Ok ()) items
  | _ -> Error "Only JSON objects are valid _meta"

let validate (meta_option : Yojson.Safe.t option) : (unit, string) result =
  match meta_option with None -> Ok () | Some json -> validate_meta_json json
