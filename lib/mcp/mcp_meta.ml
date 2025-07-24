(** Validator for MCP _meta field keys. *)

(* SPEC: "Labels MUST start with a letter and end with a letter or digit; interior characters can be letters, digits, or hyphens (-)." *)
let is_valid_label s =
  let label_re = Re.Perl.compile_pat "^[a-zA-Z]([-a-zA-Z0-9]*[a-zA-Z0-9])?$" in
  Re.execp label_re s

let%test "label start with letter" =
  let valid_starts = [ "a"; "A" ] in
  let invalid_starts = [ "1"; "-"; "_"; "." ] in
  List.for_all is_valid_label valid_starts
  && List.for_all (fun s -> not (is_valid_label s)) invalid_starts

let%test "label end with letter or digit" =
  let prefix = "valid" in
  let construct = fun s -> prefix ^ s in
  let valid_ends = List.map construct [ "z"; "Z"; "9" ] in
  let invalid_ends = List.map construct [ "-"; "_"; "." ] in
  List.for_all is_valid_label valid_ends
  && List.for_all (fun s -> not (is_valid_label s)) invalid_ends

let mcp_reserved_prefix_re =
  Re.compile
    (Re.seq
       [
         Re.bos;
         Re.alt [ Re.str "modelcontextprotocol"; Re.str "mcp" ];
         Re.char '.';
         Re.non_greedy (Re.rep Re.any);
         Re.char '/';
       ])

let%test "label interior chars letter, dig, or hyphen" =
  let prefix = "valid" in
  let postfix = "end" in
  let construct = fun s -> prefix ^ s ^ postfix in
  let valid_interior = List.map construct [ "a"; "A"; "0"; "-" ] in
  let invalid_interior = List.map construct [ "_"; "." ] in
  List.for_all (fun s -> is_valid_label s) valid_interior
  && List.for_all (fun s -> not (is_valid_label s)) invalid_interior

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

let%test "prefix matches single valid label" =
  Result.is_ok (prefix_labels "valid-label")

let%test "prefix does not match invalid label" =
  Result.is_error (prefix_labels "invalid-label-")

let%test "prefix matches N valid labels" =
  Result.is_ok (prefix_labels "valid1.valid2.valid3")

let%test "prefix does not match invalid label in N labels" =
  Result.is_error (prefix_labels "valid1.invalid-label-.valid3")

(* SPEC: "Any prefix beginning with zero or more valid labels, followed by modelcontextprotocol or mcp, followed by any valid label, is reserved for MCP use." *)
let is_reserved_prefix labels =
  let len = List.length labels in
  if len < 2 then false
  else
    let reserved_keys = [ "modelcontextprotocol"; "mcp" ] in
    (* essentially, the spec says that [ ... , reserved_label , ANY ] is reserved *)
    let check_key = List.nth labels (len - 2) in
    List.mem check_key reserved_keys

let is_mcp_reserved_prefix str =
  match prefix_labels str with
  | Ok labels -> is_reserved_prefix labels
  | Error _ -> false

(* SPEC: "For example: modelcontextprotocol.io/, mcp.dev/, api.modelcontextprotocol.org/, and tools.mcp.com/ are all reserved." *)
let%test "is_reserved_prefix MCP spec tests" =
  let spec_tests =
    [
      "modelcontextprotocol.io";
      "mcp.dev";
      "api.modelcontextprotocol.org";
      "tools.mcp.com";
    ]
  in
  List.for_all is_mcp_reserved_prefix spec_tests

let%test "is_reserved_prefix not reserved spec tests" =
  let not_spec_tests = [ "normal-prefix"; "mcp.two.labels" ] in
  (* ¬∃ == ∀¬ *)
  not (List.exists is_mcp_reserved_prefix not_spec_tests)

(* SPEC: "Unless empty, MUST begin and end with an alphanumeric character ([a-z0-9A-Z]).
MAY contain hyphens (-), underscores (_), dots (.), and alphanumerics in between." *)
let is_valid_name s =
  let name_re =
    Re.Perl.compile_pat "^[a-zA-Z0-9]([-_.a-zA-Z0-9]*[a-zA-Z0-9])?$"
  in
  s = "" || Re.execp name_re s

let%test "valid name tests" =
  let valid_names =
    [ ""; "valid"; "valid-Name"; "valid_Name"; "valid.Name"; "A" ]
  in
  List.for_all is_valid_name valid_names

let%test "valid name tests with invalid" =
  let invalid_names =
    [
      "-invalid";
      "_invalid";
      ".invalid";
      "invalid-";
      "invalid_";
      "invalid.";
      "in/valid";
    ]
  in
  List.for_all (fun s -> not (is_valid_name s)) invalid_names

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

let%test "validate_key tests" =
  let prefix = "valid" in
  let postfix = "end" in
  let join_prefixes = fun s -> prefix ^ s ^ postfix in
  let valid_prefixes = List.map join_prefixes [ "a"; "A"; "0"; "-" ] in
  let invalid_prefixes = List.map join_prefixes [ "_"; "/"; ":" ] in
  let valid_names =
    [ ""; "valid"; "valid-Name"; "valid_Name"; "valid.Name"; "A" ]
  in
  let invalid_names =
    [ "-invalid"; "_invalid"; ".invalid"; "invalid-"; "invalid_"; "invalid." ]
  in
  let cross pref name =
    List.map (fun x -> List.map (fun y -> x ^ "/" ^ y) name) pref
    |> List.flatten
  in
  let poorly_joined pref name =
    List.map (fun x -> List.map (fun y -> x ^ "//" ^ y) name) pref
    |> List.flatten
  in
  let valid_keys = cross valid_prefixes valid_names @ valid_names in
  let invalid_keys =
    cross invalid_prefixes invalid_names
    @ cross valid_prefixes invalid_names
    @ cross invalid_prefixes valid_names
    @ poorly_joined valid_prefixes valid_names
  in
  List.for_all (fun k -> Result.is_ok (validate_key k)) valid_keys
  && List.for_all (fun k -> Result.is_error (validate_key k)) invalid_keys

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
