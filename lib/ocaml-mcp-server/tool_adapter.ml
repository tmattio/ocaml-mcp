(** Adapter to register ocaml-platform-sdk tools with async MCP SDK *)

module type S = sig
  val name : string
  val description : string

  module Args : sig
    type t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
    val to_yojson : t -> Yojson.Safe.t
    val schema : unit -> Yojson.Safe.t
  end

  module Output : sig
    type t

    val to_yojson : t -> Yojson.Safe.t
  end

  module Error : sig
    type t

    val to_string : t -> string
  end

  val execute :
    sw:Eio.Switch.t ->
    env:Eio_unix.Stdenv.base ->
    Ocaml_platform_sdk.t ->
    Args.t ->
    (Output.t, Error.t) Result.t
end

(** Convert Tool.S errors to MCP errors *)
let error_to_string (type e) (module T : S with type Error.t = e) error =
  T.Error.to_string error

(** Register a Tool.S module with the async MCP SDK server *)
let register_tool (type args out err)
    (module T : S
      with type Args.t = args
       and type Output.t = out
       and type Error.t = err) server sw env sdk =
  Mcp_sdk_eio.Server.tool server T.name ~description:T.description
    ~args:(module T.Args)
    (fun args _ctx ->
      (* Create a promise and run the tool execution in a separate fiber *)
      let promise, resolver = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
        let result = 
          match T.execute ~sw ~env sdk args with
          | Ok output ->
              let json_output = T.Output.to_yojson output in
              Ok
                {
                  Mcp.Request.Tools.Call.content =
                    [
                      Mcp.Types.Content.Text
                        {
                          type_ = "text";
                          text = Yojson.Safe.to_string json_output;
                          meta = None;
                        };
                    ];
                  is_error = Some false;
                  structured_content = Some json_output;
                  meta = None;
                }
          | Error err ->
              Ok
                {
                  Mcp.Request.Tools.Call.content =
                    [
                      Mcp.Types.Content.Text
                        {
                          type_ = "text";
                          text = error_to_string (module T) err;
                          meta = None;
                        };
                    ];
                  is_error = Some true;
                  structured_content = None;
                  meta = None;
                }
        in
        Eio.Promise.resolve resolver result);
      promise)

(** Register all ocaml-platform-sdk tools as async *)
let register_all server sw env sdk =
  (* Dune tools *)
  register_tool (module Build_status) server sw env sdk;
  register_tool (module Build_target) server sw env sdk;
  register_tool (module Run_tests) server sw env sdk;

  (* OCaml analysis tools *)
  register_tool (module Module_signature) server sw env sdk;
  register_tool (module Find_definition) server sw env sdk;
  register_tool (module Find_references) server sw env sdk;
  register_tool (module Type_at_pos) server sw env sdk;
  register_tool (module Project_structure) server sw env sdk;
  register_tool (module Eval) server sw env sdk;

  (* File system tools with OCaml superpowers *)
  register_tool (module Fs_read) server sw env sdk;
  register_tool (module Fs_write) server sw env sdk;
  register_tool (module Fs_edit) server sw env sdk