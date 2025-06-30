(** Dune RPC client with registry polling using Eio *)

open Eio

(* Import Dune RPC types *)
module Drpc = Dune_rpc.V1

(* Setup logging *)
let src = Logs.Src.create "dune-rpc-client" ~doc:"Dune RPC Client logging"
module Log = (val Logs.src_log src : Logs.LOG)

(* Request ID counter *)
module Request_id = struct
  type t = { mutable counter : int; mutex : Eio.Mutex.t }
  
  let create () = { counter = 0; mutex = Eio.Mutex.create () }
  
  let next t =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
      let id = t.counter in
      t.counter <- t.counter + 1;
      Printf.sprintf "dune-rpc-%d" id)
end

(* Registry polling module following OCaml LSP pattern *)
module Registry_poll = struct
  type instance = {
    root : string;
    pid : int option; [@warning "-69"]
    socket : string option;
  }

  let read_file ~fs path =
    try
      let content = Eio.Path.load (Eio.Path.(fs / path)) in
      Ok content
    with 
    | Eio.Io (Eio.Fs.E Not_found _, _) -> Error "File not found"
    | exn -> Error (Printexc.to_string exn)

  let parse_registry_entry content =
    try
      match Csexp.parse_string content with
      | Ok (Csexp.List [ Csexp.Atom "3"; Csexp.List fields ]) ->
          (* Version 3 format *)
          let root = ref None in
          let pid = ref None in
          List.iter
            (function
              | Csexp.List [ Csexp.Atom "root"; Csexp.Atom r ] -> root := Some r
              | Csexp.List [ Csexp.Atom "pid"; Csexp.Atom p ] -> (
                  try pid := Some (int_of_string p) 
                  with 
                  | Failure _ -> () (* Invalid integer format *)
                  | Invalid_argument _ -> ())
              | _ -> ())
            fields;
          Option.map (fun r -> { root = r; pid = !pid; socket = None }) !root
      | Ok
          (Csexp.List
             [
               Csexp.Atom "2";
               Csexp.List [ Csexp.Atom "root"; Csexp.Atom root ];
               Csexp.List [ Csexp.Atom "pid"; Csexp.Atom pid_str ];
             ]) ->
          (* Version 2 format *)
          let pid = 
            try Some (int_of_string pid_str) 
            with Failure _ | Invalid_argument _ -> None 
          in
          Some { root; pid; socket = None }
      | _ -> None
    with
    | Csexp.Parser.Parse_error _ -> None
    | Invalid_argument _ -> None
    | _ -> None

  let poll ~fs registry_path =
    try
      let entries = Eio.Path.read_dir (Eio.Path.(fs / registry_path)) in
      let instances = ref [] in
      List.iter
        (fun entry ->
          if
            (not (String.starts_with ~prefix:"." entry))
            && not (String.ends_with ~suffix:".socket" entry)
          then
            let entry_path = Filename.concat registry_path entry in
            match read_file ~fs entry_path with
            | Ok content -> (
                match parse_registry_entry content with
                | Some inst ->
                    let socket_path =
                      Filename.concat registry_path (entry ^ ".socket")
                    in
                    let inst =
                      try
                        ignore (Eio.Path.load (Eio.Path.(fs / socket_path)));
                        { inst with socket = Some socket_path }
                      with 
                      | Eio.Io (Eio.Fs.E Not_found _, _) -> inst
                      | _ -> inst
                    in
                    instances := inst :: !instances
                | None -> ())
            | Error _ -> ())
        entries;
      Ok !instances
    with 
    | Eio.Io (Eio.Fs.E Not_found _, _) -> Ok []
    | exn -> Error (Printexc.to_string exn)
end

type diagnostic = {
  file : string;
  line : int;
  column : int;
  message : string;
  severity : [ `Error | `Warning ];
}

type progress =
  | Waiting
  | In_progress of { complete : int; remaining : int; failed : int }
  | Failed
  | Interrupted
  | Success

type session = {
  flow : Eio.Flow.two_way_ty Eio.Resource.t;
  buf_read : Buf_read.t;
  buf_write : Buf_write.t;
  id : Drpc.Id.t; [@warning "-69"]
  request_id : Request_id.t;
}

type connection_state = Disconnected | Connected of session | Closed

type t = {
  sw : Switch.t;
  root : string;
  mutable state : connection_state;
  registry_path : string option;
  diagnostics : (string, diagnostic list) Hashtbl.t;
  mutable progress : progress;
  mutex : Eio.Mutex.t;
  env : Eio_unix.Stdenv.base;
  mutable last_poll_error : string option;
}

let default_registry_path () =
  match Sys.getenv_opt "XDG_RUNTIME_DIR" with
  | Some dir -> Some (Filename.concat dir "dune-rpc")
  | None -> (
      match Sys.getenv_opt "HOME" with
      | Some home -> Some (Filename.concat home ".cache/dune/rpc")
      | None -> None)

let create ~sw ~env ~root =
  let registry_path = default_registry_path () in
  let diagnostics = Hashtbl.create 16 in
  let mutex = Eio.Mutex.create () in
  {
    sw;
    root;
    state = Disconnected;
    registry_path;
    diagnostics;
    progress = Waiting;
    mutex;
    env;
    last_poll_error = None;
  }

(* Find matching Dune instance for our root *)
let find_matching_instance instances root =
  (* First try exact match *)
  match
    List.find_opt (fun inst -> inst.Registry_poll.root = root) instances
  with
  | Some _ as result -> result
  | None ->
      (* Then try parent directories *)
      List.find_opt
        (fun inst ->
          let inst_root = inst.Registry_poll.root in
          String.starts_with ~prefix:inst_root root
          && (String.length root = String.length inst_root
             || root.[String.length inst_root] = '/'))
        instances

(* Write a Csexp to the buffer *)
let write_csexp buf_write csexp =
  let s = Csexp.to_string csexp in
  Buf_write.string buf_write s

(* Read a Csexp from the buffer using the Parser module for robust parsing *)
let read_csexp buf_read =
  let module Lexer = Csexp.Parser.Lexer in
  let module Stack = Csexp.Parser.Stack in
  
  let lexer = Lexer.create () in
  let rec loop stack =
    match Buf_read.peek_char buf_read with
    | None ->
        Lexer.feed_eoi lexer;
        Error "Unexpected end of input"
    | Some _ ->
        let c = Buf_read.any_char buf_read in
        let token = Lexer.feed lexer c in
        match token with
        | Atom n ->
            (* Read n bytes for the atom *)
            let atom_bytes = Buf_read.take n buf_read in
            let stack = Stack.add_atom atom_bytes stack in
            (match stack with
            | Sexp (sexp, Empty) -> Ok sexp
            | _ -> loop stack)
        | Lparen | Rparen | Await as token ->
            let stack = Stack.add_token token stack in
            match stack with
            | Sexp (sexp, Empty) -> Ok sexp
            | _ -> loop stack
  in
  
  try
    loop Stack.Empty
  with
  | End_of_file -> Error "Connection closed"
  | exn -> Error (Printf.sprintf "Parse error: %s" (Printexc.to_string exn))

(* Initialize RPC session *)
let initialize_session ~flow ~buf_read ~buf_write =
  let id = Drpc.Id.make (Csexp.Atom "ocaml-mcp") in
  let request_id = Request_id.create () in
  
  (* Send initialize request *)
  let req_id = Request_id.next request_id in
  let csexp =
    Csexp.List
      [
        Csexp.Atom "request";
        Csexp.List [ Csexp.Atom "id"; Csexp.Atom req_id ];
        Csexp.Atom "initialize";
        Csexp.List [ Csexp.Atom "version"; Csexp.Atom "1.0" ];
      ]
  in
  write_csexp buf_write csexp;
  Buf_write.flush buf_write;
  (* Write the buffer contents to the flow *)
  let s = Csexp.to_string csexp in
  Eio.Flow.copy_string s flow;

  (* Read response *)
  match read_csexp buf_read with
  | Ok (Csexp.List [ Csexp.Atom "response"; _; Csexp.Atom "ok"; _ ]) ->
      Ok { flow; buf_read; buf_write; id; request_id }
  | Ok (Csexp.List [ Csexp.Atom "response"; _; Csexp.Atom "error"; msg ]) ->
      let error_msg =
        match msg with 
        | Csexp.Atom s -> s 
        | Csexp.List _ -> "Complex error response"
      in
      Error (Printf.sprintf "Initialize failed: %s" error_msg)
  | Ok sexp -> 
      Error (Printf.sprintf "Invalid initialize response: %s" (Csexp.to_string sexp))
  | Error msg -> Error msg

(* Connect to a Dune instance *)
let connect_to_instance ~sw ~net instance =
  match instance.Registry_poll.socket with
  | None -> Error "No socket path available"
  | Some socket_path -> (
      try
        let addr = `Unix socket_path in
        let socket = Eio.Net.connect ~sw net addr in
        let flow = (socket :> Eio.Flow.two_way_ty Eio.Resource.t) in
        let buf_read = Buf_read.of_flow ~max_size:Int.max_int flow in
        let buf_write = Buf_write.create 4096 in
        match initialize_session ~flow ~buf_read ~buf_write with
        | Ok session -> Ok session
        | Error msg ->
            Eio.Flow.close socket;
            Error msg
      with
      | Eio.Io _ as exn -> 
          Error (Printf.sprintf "Connection failed: %s" (Printexc.to_string exn))
      | exn -> Error (Printexc.to_string exn))

(* Subscribe to diagnostics and progress *)
let subscribe_to_events session _t =
  (* Subscribe to diagnostics *)
  let diag_req_id = Request_id.next session.request_id in
  let diag_msg =
    Csexp.List
      [
        Csexp.Atom "request";
        Csexp.List [ Csexp.Atom "id"; Csexp.Atom diag_req_id ];
        Csexp.Atom "subscribe";
        Csexp.Atom "diagnostics";
      ]
  in
  write_csexp session.buf_write diag_msg;
  Buf_write.flush session.buf_write;
  let s = Csexp.to_string diag_msg in
  Eio.Flow.copy_string s session.flow;

  (* Subscribe to progress *)
  let progress_req_id = Request_id.next session.request_id in
  let progress_msg =
    Csexp.List
      [
        Csexp.Atom "request";
        Csexp.List [ Csexp.Atom "id"; Csexp.Atom progress_req_id ];
        Csexp.Atom "subscribe";
        Csexp.Atom "progress";
      ]
  in
  write_csexp session.buf_write progress_msg;
  Buf_write.flush session.buf_write;
  let s = Csexp.to_string progress_msg in
  Eio.Flow.copy_string s session.flow

(* Parse diagnostic from Csexp - based on Dune RPC protocol *)
let parse_diagnostic csexp =
  let open Csexp in
  (* Helper to find a field in an association list *)
  let find_field name fields =
    let rec find = function
      | [] -> None
      | List [ Atom n; value ] :: _ when n = name -> Some value
      | _ :: rest -> find rest
    in
    find fields
  in

  (* Parse severity *)
  let parse_severity = function
    | Atom "error" -> Some `Error
    | Atom "warning" -> Some `Warning
    | _ -> None
  in

  (* Parse location *)
  let parse_loc = function
    | List fields -> (
        let start_pos = find_field "start" fields in
        match start_pos with
        | Some (List pos_fields) -> (
            let fname = find_field "pos_fname" pos_fields in
            let lnum = find_field "pos_lnum" pos_fields in
            let cnum = find_field "pos_cnum" pos_fields in
            let bol = find_field "pos_bol" pos_fields in
            match (fname, lnum, cnum, bol) with
            | ( Some (Atom file),
                Some (Atom line_str),
                Some (Atom cnum_str),
                Some (Atom bol_str) ) -> (
                try
                  let line = int_of_string line_str in
                  let cnum = int_of_string cnum_str in
                  let bol = int_of_string bol_str in
                  Some (file, line, cnum - bol)
                with _ -> None)
            | _ -> None)
        | _ -> None)
    | _ -> None
  in

  (* Parse the diagnostic *)
  match csexp with
  | List fields -> (
      let message = find_field "message" fields in
      let severity =
        Option.bind (find_field "severity" fields) parse_severity
      in
      let loc = Option.bind (find_field "loc" fields) parse_loc in
      match (message, loc) with
      | Some (Atom msg), Some (file, line, column) ->
          Some
            {
              file;
              line;
              column;
              message = msg;
              severity = Option.value severity ~default:`Warning;
            }
      | _ -> None)
  | _ -> None

(* Process incoming messages *)
let process_messages t session =
  try
    match read_csexp session.buf_read with
    | Error _ -> false (* Connection closed *)
    | Ok csexp ->
        (* Parse different message types *)
        (match csexp with
        | Csexp.List
            [ Csexp.Atom "notification"; Csexp.Atom "diagnostic"; payload ] -> (
            (* Single diagnostic event *)
            match payload with
            | Csexp.List [ Csexp.Atom "Add"; diag_sexp ] -> (
                match parse_diagnostic diag_sexp with
                | Some diag ->
                    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
                        let current =
                          Hashtbl.find_opt t.diagnostics diag.file
                          |> Option.value ~default:[]
                        in
                        Hashtbl.replace t.diagnostics diag.file (diag :: current))
                | None -> ())
            | Csexp.List [ Csexp.Atom "Remove"; diag_sexp ] -> (
                (* For remove, we need at least the file to clear diagnostics *)
                match parse_diagnostic diag_sexp with
                | Some diag ->
                    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
                        (* Remove this specific diagnostic or clear file *)
                        let current =
                          Hashtbl.find_opt t.diagnostics diag.file
                          |> Option.value ~default:[]
                        in
                        let filtered =
                          List.filter
                            (fun d ->
                              not (d.line = diag.line && d.column = diag.column))
                            current
                        in
                        if filtered = [] then
                          Hashtbl.remove t.diagnostics diag.file
                        else Hashtbl.replace t.diagnostics diag.file filtered)
                | None -> ())
            | _ -> ())
        | Csexp.List
            [
              Csexp.Atom "notification";
              Csexp.Atom "diagnostics";
              Csexp.List events;
            ] ->
            (* Multiple diagnostic events *)
            List.iter
              (function
                | Csexp.List [ Csexp.Atom "Add"; diag_sexp ] -> (
                    match parse_diagnostic diag_sexp with
                    | Some diag ->
                        Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
                            let current =
                              Hashtbl.find_opt t.diagnostics diag.file
                              |> Option.value ~default:[]
                            in
                            Hashtbl.replace t.diagnostics diag.file
                              (diag :: current))
                    | None -> ())
                | Csexp.List [ Csexp.Atom "Remove"; diag_sexp ] -> (
                    match parse_diagnostic diag_sexp with
                    | Some diag ->
                        Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
                            Hashtbl.remove t.diagnostics diag.file)
                    | None -> ())
                | _ -> ())
              events
        | Csexp.List
            [ Csexp.Atom "notification"; Csexp.Atom "progress"; progress_csexp ]
          -> (
            (* Handle progress update *)
            match progress_csexp with
            | Csexp.Atom "Waiting" -> t.progress <- Waiting
            | Csexp.Atom "Failed" -> t.progress <- Failed
            | Csexp.Atom "Interrupted" -> t.progress <- Interrupted
            | Csexp.Atom "Success" -> t.progress <- Success
            | Csexp.List [ Csexp.Atom "In_progress"; Csexp.List fields ] ->
                let find_int name fields =
                  let rec find = function
                    | [] -> None
                    | Csexp.List [ Csexp.Atom n; Csexp.Atom v ] :: _
                      when n = name -> (
                              try Some (int_of_string v) 
                        with Failure _ | Invalid_argument _ -> None)
                    | _ :: rest -> find rest
                  in
                  find fields
                in
                let complete =
                  find_int "complete" fields |> Option.value ~default:0
                in
                let remaining =
                  find_int "remaining" fields |> Option.value ~default:0
                in
                let failed =
                  find_int "failed" fields |> Option.value ~default:0
                in
                t.progress <- In_progress { complete; remaining; failed }
            | _ -> ())
        | _ -> ());
        true
  with
  | End_of_file -> false
  | Failure _ | Invalid_argument _ -> true
  | exn -> 
      Log.debug (fun m -> m "Unexpected error in process_messages: %s" (Printexc.to_string exn));
      true

(* Poll for Dune instances and connect if found *)
let poll_and_connect t =
  Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
      match t.state with
      | Connected _ | Closed -> ()
      | Disconnected -> (
          match t.registry_path with
          | None -> ()
          | Some registry_path -> (
              let fs = Eio.Stdenv.fs t.env in
              let net = Eio.Stdenv.net t.env in
              match Registry_poll.poll ~fs registry_path with
              | Error msg ->
                  if t.last_poll_error <> Some msg then
                    t.last_poll_error <- Some msg (* Log error if needed *)
              | Ok instances -> (
                  t.last_poll_error <- None;
                  match find_matching_instance instances t.root with
                  | None -> ()
                  | Some instance -> (
                      match connect_to_instance ~sw:t.sw ~net instance with
                      | Ok session ->
                          subscribe_to_events session t;
                          t.state <- Connected session
                      | Error _msg ->
                          (* Ignore connection errors for resilience *)
                          ())))))

(* Main polling loop *)
let run t =
  let clock = Eio.Stdenv.clock t.env in
  let rec loop () =
    poll_and_connect t;

    (* Process messages if connected *)
    (match t.state with
    | Connected session ->
        if not (process_messages t session) then
          (* Connection lost *)
          Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
              Eio.Flow.shutdown session.flow `All;
              t.state <- Disconnected)
    | _ -> ());

    (* Sleep for 250ms before next poll *)
    Eio.Time.sleep clock 0.25;

    match t.state with Closed -> () | _ -> loop ()
  in
  loop ()

(* Get diagnostics for a file *)
let get_diagnostics t ~file =
  Eio.Mutex.use_ro t.mutex (fun () ->
      if file = "" then
        (* Return all diagnostics *)
        Hashtbl.fold (fun _file diags acc -> diags @ acc) t.diagnostics []
      else Hashtbl.find_opt t.diagnostics file |> Option.value ~default:[])

(* Get current build progress *)
let get_progress t = Eio.Mutex.use_ro t.mutex (fun () -> t.progress)

(* Close the client *)
let close t =
  Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
      match t.state with
      | Connected session ->
          Eio.Flow.shutdown session.flow `All;
          t.state <- Closed
      | _ -> t.state <- Closed)