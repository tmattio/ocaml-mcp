(** Merlin library integration *)

open Eio

(* Import Merlin modules *)
module Mconfig = Merlin_kernel.Mconfig
module Msource = Merlin_kernel.Msource
module Mpipeline = Merlin_kernel.Mpipeline
module Mbrowse = Merlin_kernel.Mbrowse
module Mtyper = Merlin_kernel.Mtyper

type signature_item =
  | Value of string * string
  | Type of string * string
  | Module of string * signature_item list
  | Exception of string * string
[@@deriving yojson]

(* Thread-safe pipeline management using Eio *)
module Pipeline = struct
  type t = { mutex : Eio.Mutex.t }

  let create ~sw:_ =
    let mutex = Eio.Mutex.create () in
    { mutex }

  let use t ~config ~source ~f =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
        let pipeline = Mpipeline.make config source in
        try Ok (f pipeline) with exn -> Error exn)
end

type t = {
  pipeline : Pipeline.t;
  project_root : string;
  sw : Switch.t; [@warning "-69"]
  (* Cache for loaded file contents *)
  file_cache : (string, string) Hashtbl.t;
}

let create ~sw ~mgr:_ ~project_root =
  let pipeline = Pipeline.create ~sw in
  let file_cache = Hashtbl.create 16 in
  { pipeline; project_root; sw; file_cache }

(* Helper to get Merlin config for a file *)
let get_config t ~file =
  let filename =
    if Filename.is_relative file then Filename.concat t.project_root file
    else file
  in
  let config = Mconfig.initial in
  (* Set the filename in the config *)
  let query = { config.query with filename } in
  { config with query }

(* Helper to run queries on the pipeline *)
let with_pipeline t ~file ~content f =
  let config = get_config t ~file in
  let source = Msource.make content in
  Pipeline.use t.pipeline ~config ~source ~f

(* Extract signature items from outline *)
let rec outline_to_signature_items items =
  List.filter_map
    (fun item ->
      let open Query_protocol in
      match item.outline_kind with
      | `Value ->
          let type_info = Option.value ~default:"" item.outline_type in
          Some (Value (item.outline_name, type_info))
      | `Type ->
          let type_info = Option.value ~default:"" item.outline_type in
          Some (Type (item.outline_name, type_info))
      | `Module ->
          (* Recursively process module children *)
          let children = outline_to_signature_items item.children in
          Some (Module (item.outline_name, children))
      | `Exn ->
          let type_info = Option.value ~default:"" item.outline_type in
          Some (Exception (item.outline_name, type_info))
      | `Constructor | `Label | `Modtype | `Class | `ClassType | `Method -> None)
    items

let get_module_signature t ~module_path =
  (* Create a file that opens the module to analyze its contents *)
  let module_name = String.concat "." module_path in
  let content = Printf.sprintf "module M = %s\n" module_name in
  let dummy_file = Printf.sprintf "<module-%s>" module_name in

  match
    with_pipeline t ~file:dummy_file ~content (fun pipeline ->
        (* First try to get the module type using Type_enclosing *)
        let pos = `Logical (1, String.length content - 1) in
        match
          Query_commands.dispatch pipeline
            (Query_protocol.Type_enclosing (None, pos, Some 0))
        with
        | [] ->
            (* Fallback: try to get outline of the opened module *)
            let outline =
              Query_commands.dispatch pipeline Query_protocol.Outline
            in
            outline_to_signature_items outline
        | (_loc, `String type_str, _) :: _ ->
            (* Parse the module signature string *)
            (* For now, return a simple representation *)
            [ Value ("<module signature>", type_str) ]
        | _ -> [])
  with
  | Ok items -> items
  | Error _ -> (
      (* If that fails, try to load the module's source file *)
      match module_path with
      | [ module_name ] ->
          (* Try to find and analyze the module's .ml or .mli file *)
          let possible_files =
            [
              Filename.concat t.project_root
                (String.uncapitalize_ascii module_name ^ ".mli");
              Filename.concat t.project_root
                (String.uncapitalize_ascii module_name ^ ".ml");
            ]
          in
          let rec try_files = function
            | [] -> []
            | file :: rest ->
                if Sys.file_exists file then
                  match
                    let ch = open_in file in
                    let content =
                      try really_input_string ch (in_channel_length ch)
                      with exn ->
                        close_in ch;
                        raise exn
                    in
                    close_in ch;
                    with_pipeline t ~file ~content (fun pipeline ->
                        let outline =
                          Query_commands.dispatch pipeline
                            Query_protocol.Outline
                        in
                        outline_to_signature_items outline)
                  with
                  | Ok items -> items
                  | Error _ -> try_files rest
                else try_files rest
          in
          try_files possible_files
      | _ -> [])

let type_enclosing t ~file ~line ~col =
  (* Get the file content from cache *)
  let content = Option.value (Hashtbl.find_opt t.file_cache file) ~default:"" in

  match
    with_pipeline t ~file ~content (fun pipeline ->
        let pos = `Logical (line, col) in
        (* Type_enclosing takes: expression_under_cursor, position, index
       - expression_under_cursor: None to use default behavior
       - position: The position in the source
       - index: Some 0 to get the innermost enclosing type *)
        let query = Query_protocol.Type_enclosing (None, pos, Some 0) in
        Query_commands.dispatch pipeline query)
  with
  | Ok enclosings -> (
      match enclosings with
      | [] -> None
      | (_loc, `String type_str, _) :: _ -> Some type_str
      | (_loc, `Index _, _) :: _ -> None)
  | Error _ -> None

let complete t ~file ~line ~col ~prefix =
  (* Get the file content from cache *)
  let content = Option.value (Hashtbl.find_opt t.file_cache file) ~default:"" in

  match
    with_pipeline t ~file ~content (fun pipeline ->
        let pos = `Logical (line, col) in
        (* Complete_prefix takes: prefix, position, labels, is_label, exact_prefix *)
        let query =
          Query_protocol.Complete_prefix (prefix, pos, [], false, true)
        in
        Query_commands.dispatch pipeline query)
  with
  | Ok response -> (
      let
      (* Access the completion entries from the response *)
      open
        Query_protocol in
      match response.entries with
      | [] -> []
      | entries ->
          List.map (fun entry -> (entry.Compl.name, entry.Compl.desc)) entries)
  | Error _ -> []

let load_file t ~file ~content =
  (* Cache the file content for use in queries *)
  Hashtbl.replace t.file_cache file content

let close _t =
  (* Cleanup is handled by switch *)
  ()
