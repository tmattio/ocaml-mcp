(** OCamlformat client using the library directly instead of RPC *)


(* Default formatting options *)
let default_conf = 
  let open Ocamlformat_lib in
  match Conf.default |> Conf.update_value ~name:"module-item-spacing" ~value:"compact" with
  | Ok conf -> (
    match Conf.update_value conf ~name:"margin" ~value:"63" with
    | Ok conf -> conf
    | Error _ -> Conf.default
  )
  | Error _ -> Conf.default

type t = {
  conf : Ocamlformat_lib.Conf.t;
  mutex : Eio.Mutex.t;
}

let create () = 
  {
    conf = default_conf;
    mutex = Eio.Mutex.create ();
  }

let format_doc t ~path ~content =
  Eio.Mutex.use_ro t.mutex (fun () ->
    try
      let open Ocamlformat_lib in
      (* Use the default configuration for now *)
      let conf = t.conf in
      
      (* Try different formatting modes in order *)
      let try_format format_type =
        Translation_unit.parse_and_format format_type ~input_name:path ~source:content conf
      in
      
      (* Try formatting as implementation first, then other types *)
      let rec try_formats = function
        | [] -> Error "Failed to format: no suitable parser found"
        | format_type :: rest ->
          match try_format format_type with
          | Ok formatted -> Ok formatted
          | Error _ -> try_formats rest
      in
      
      try_formats [Use_file; Signature; Expression; Core_type; Module_type]
    with
    | exn -> Error (Printf.sprintf "Formatting error: %s" (Printexc.to_string exn))
  )

let format_type t ~typ =
  Eio.Mutex.use_ro t.mutex (fun () ->
    try
      let open Ocamlformat_lib in
      match Translation_unit.parse_and_format Core_type ~input_name:"<type>" ~source:typ t.conf with
      | Ok formatted -> Ok formatted
      | Error e ->
        let msg = Format.asprintf "%a" (Translation_unit.Error.print ~debug:false ~quiet:false) e in
        Error (`Msg msg)
    with
    | exn -> Error (`Msg (Printexc.to_string exn))
  )

