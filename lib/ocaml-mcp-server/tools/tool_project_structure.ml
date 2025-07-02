(** Project structure tool *)

open Mcp_sdk
open Eio

(* Tool argument types *)
type args = unit [@@deriving yojson]

let name = "ocaml/project-structure"
let description = "Return project layout, libraries, executables"
let src = Logs.Src.create "project-structure" ~doc:"Project structure tool"

module Log = (val Logs.src_log src : Logs.LOG)

type component_type = Library | Executable

type component = {
  component_type : component_type;
  name : string;
  directory : string;
  source_dir : string;
  public_name : string option;
  modules : string list;
  dependencies : string list;
}

(* Parse s-expression atom *)
let parse_atom = function
  | Csexp.Atom s -> s
  | List _ -> failwith "Expected atom, got list"

(* Parse s-expression list *)
let parse_list f = function Csexp.List l -> List.map f l | _ -> []

(* Find a field in an association list *)
let find_field name fields =
  List.find_opt
    (function
      | Csexp.List [ Csexp.Atom n; _ ] when n = name -> true | _ -> false)
    fields
  |> Option.map (function
       | Csexp.List [ _; v ] -> v
       | _ -> failwith "Invalid field")

(* Extract string from field *)
let get_string name fields =
  match find_field name fields with Some (Csexp.Atom s) -> Some s | _ -> None

(* Extract list of strings from field *)
let get_string_list name fields =
  find_field name fields
  |> Option.map (parse_list parse_atom)
  |> Option.value ~default:[]

(* Extract bool from field *)
let get_bool name fields =
  match find_field name fields with
  | None -> false
  | Some (Csexp.Atom "true") -> true
  | Some (Csexp.Atom _) -> false
  | Some _ -> false

let parse_dune_describe_output output =
  try
    (* Trim any trailing whitespace/newlines *)
    let output = String.trim output in
    match Csexp.parse_string output with
    | Ok sexp ->
        let root = ref "" in
        let uid_to_name = Hashtbl.create 100 in
        let components = ref [] in

        (* Helper to traverse the sexp structure *)
        let process_sexp = function
          | Csexp.List items ->
              List.iter
                (function
                  | Csexp.List [ Csexp.Atom "root"; Csexp.Atom r ] ->
                      Log.debug (fun m -> m "Found root: %s" r);
                      root := r
                  | Csexp.List [ Csexp.Atom "library"; Csexp.List fields ] -> (
                      match
                        (get_string "uid" fields, get_string "name" fields)
                      with
                      | Some uid, Some name -> Hashtbl.add uid_to_name uid name
                      | _ -> ())
                  | _ -> ())
                items;

              (* Second pass for components *)
              List.iter
                (fun item ->
                  try
                    match item with
                    | Csexp.List [ Csexp.Atom "library"; Csexp.List fields ] ->
                        let is_local = get_bool "local" fields in
                        if is_local then
                          let name =
                            Option.value (get_string "name" fields) ~default:""
                          in
                          let source_dir =
                            Option.value
                              (get_string "source_dir" fields)
                              ~default:""
                          in
                          let modules_info =
                            find_field "modules" fields
                            |> Option.value ~default:(Csexp.List [])
                          in
                          let modules =
                            match modules_info with
                            | Csexp.List mods ->
                                List.filter_map
                                  (function
                                    | Csexp.List mod_fields ->
                                        get_string "name" mod_fields
                                    | _ -> None)
                                  mods
                            | _ -> []
                          in
                          let requires =
                            try get_string_list "requires" fields
                            with e ->
                              Log.err (fun m ->
                                  m "Failed to get requires: %s"
                                    (Printexc.to_string e));
                              []
                          in
                          let dependencies =
                            List.filter_map
                              (fun uid -> Hashtbl.find_opt uid_to_name uid)
                              requires
                          in
                          let src_dir =
                            if
                              String.starts_with ~prefix:"_build/default/"
                                source_dir
                            then
                              String.sub source_dir 15
                                (String.length source_dir - 15)
                            else source_dir
                          in
                          components :=
                            {
                              component_type = Library;
                              name;
                              directory = src_dir;
                              source_dir;
                              public_name = None;
                              modules;
                              dependencies;
                            }
                            :: !components
                    | Csexp.List [ Csexp.Atom "executables"; Csexp.List fields ]
                      ->
                        let names = get_string_list "names" fields in
                        (* Try to get source_dir field, fall back to deriving from modules *)
                        let src_dir =
                          match get_string "source_dir" fields with
                          | Some dir
                            when String.starts_with ~prefix:"_build/default/"
                                   dir ->
                              String.sub dir 15 (String.length dir - 15)
                          | Some dir -> dir
                          | None -> (
                              (* Fall back to extracting from module paths *)
                              try
                                match find_field "modules" fields with
                                | Some (Csexp.List modules_list) ->
                                    (* Find the first module with an impl path *)
                                    let rec find_impl_dir = function
                                      | [] -> ""
                                      | Csexp.List mod_fields :: rest -> (
                                          match
                                            find_field "impl" mod_fields
                                          with
                                          | Some
                                              (Csexp.List
                                                 [ Csexp.Atom impl_path ])
                                          | Some (Csexp.Atom impl_path) ->
                                              if
                                                String.starts_with
                                                  ~prefix:"_build/default/"
                                                  impl_path
                                              then
                                                let dir =
                                                  Filename.dirname impl_path
                                                in
                                                String.sub dir 15
                                                  (String.length dir - 15)
                                              else Filename.dirname impl_path
                                          | _ -> find_impl_dir rest)
                                      | _ :: rest -> find_impl_dir rest
                                    in
                                    find_impl_dir modules_list
                                | _ -> ""
                              with _ -> "")
                        in
                        let requires =
                          try
                            let req = get_string_list "requires" fields in
                            req
                          with e ->
                            Log.err (fun m ->
                                m "Failed to get executable requires: %s"
                                  (Printexc.to_string e));
                            []
                        in
                        let dependencies =
                          List.filter_map
                            (fun uid -> Hashtbl.find_opt uid_to_name uid)
                            requires
                        in
                        List.iter
                          (fun name ->
                            components :=
                              {
                                component_type = Executable;
                                name;
                                directory = src_dir;
                                source_dir = src_dir;
                                public_name = None;
                                modules = [];
                                dependencies;
                              }
                              :: !components)
                          names
                    | _ -> ()
                  with e ->
                    Log.err (fun m ->
                        m "Error processing item: %s" (Printexc.to_string e)))
                items
          | _ -> failwith "Expected list at top level"
        in

        process_sexp sexp;
        if !root = "" then Error "No root found in dune describe output"
        else Ok (!root, List.rev !components)
    | Error (_, msg) -> Error ("Parse error: " ^ msg)
  with e -> Error ("Parse error: " ^ Printexc.to_string e)

let format_component ~project_root:_ comp =
  let type_str =
    match comp.component_type with
    | Library -> "Library"
    | Executable -> "Executable"
  in
  let lines =
    [
      Printf.sprintf "COMPONENT: %s" type_str;
      Printf.sprintf "  Name: %s" comp.name;
      Printf.sprintf "  Directory: %s" comp.directory;
    ]
  in
  let lines =
    match comp.public_name with
    | Some pub -> lines @ [ Printf.sprintf "  Public Name: %s" pub ]
    | None -> lines
  in
  let lines =
    if comp.modules <> [] then
      lines
      @ [
          Printf.sprintf "  Public Modules: %s"
            (String.concat ", " comp.modules);
        ]
    else lines
  in
  let lines =
    if comp.dependencies <> [] then
      lines
      @ [
          Printf.sprintf "  Dependencies: %s"
            (String.concat ", " comp.dependencies);
        ]
    else lines
  in
  let lines =
    match comp.component_type with
    | Library ->
        lines
        @ [
            Printf.sprintf "  Action: Build: dune build @%s/all" comp.directory;
          ]
    | Executable ->
        let exe_path =
          if comp.directory = "" then comp.name
          else Filename.concat comp.directory comp.name
        in
        lines
        @ [
            Printf.sprintf "  Action: Build: dune build %s.exe" exe_path;
            Printf.sprintf "  Action: Run: dune exec %s.exe" exe_path;
          ]
  in
  String.concat "\n" lines

let handle _sw env project_root _args _ctx =
  Log.info (fun m ->
      m "project-structure tool called with project_root: %s" project_root);
  Log.debug (fun m -> m "Running dune describe workspace");

  let process_mgr = Stdenv.process_mgr env in

  (* Run dune describe using Eio.Process *)
  try
    let output_buf = Buffer.create 1024 in
    Process.run process_mgr
      [ "dune"; "-C"; project_root; "describe"; "workspace"; "--format=csexp" ]
      ~stdout:(Flow.buffer_sink output_buf);

    let output = Buffer.contents output_buf in

    match parse_dune_describe_output output with
    | Ok (root, components) ->
        Log.debug (fun m -> m "Parsed %d components" (List.length components));
        let header =
          Printf.sprintf "Project Root: %s\nBuild Context: default\n" root
        in
        let formatted_components =
          List.map (format_component ~project_root) components
          |> String.concat "\n\n"
        in
        Ok (Tool_result.text (header ^ "\n" ^ formatted_components))
    | Error msg ->
        Log.err (fun m -> m "Failed to parse dune describe output: %s" msg);
        Error msg
  with exn ->
    let msg =
      match exn with
      | Eio.Exn.Io (Eio.Process.E _, _) -> "dune describe failed"
      | _ ->
          Printf.sprintf "Error running dune describe: %s"
            (Printexc.to_string exn)
    in
    Log.err (fun m -> m "%s" msg);
    Error msg

let register server ~sw ~env ~project_root =
  Log.debug (fun m ->
      m "Registering project-structure tool with project_root: %s" project_root);
  Server.tool server name ~description (fun () _ctx ->
      handle sw env project_root () _ctx)
