module type S = sig
  val name : string
  val description : string

  module Args : sig
    type t

    val json : t Jsont.t
    val schema : unit -> Jsont.json
  end

  module Output : sig
    type t

    val json : t Jsont.t
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

module Build_status = Build_status
module Build_target = Build_target
module Eval = Eval
module Find_definition = Find_definition
module Find_references = Find_references
module Fs_edit = Fs_edit
module Fs_read = Fs_read
module Fs_write = Fs_write
module Module_signature = Module_signature
module Project_structure = Project_structure
module Run_tests = Run_tests
module Type_at_pos = Type_at_pos
