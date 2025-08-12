(** MCP SDK with Eio async support using the common functor implementation *)

(* Define Json_converter module type *)
module type Json_converter = sig
  type t

  val to_yojson : t -> Yojson.Safe.t
  val of_yojson : Yojson.Safe.t -> (t, string) result
  val schema : unit -> Yojson.Safe.t
end

(* Re-export common modules *)
module Context = struct
  include Mcp_sdk.Context

  let report_progress_async t ~sw ~progress ?total () =
    Eio.Fiber.fork ~sw (fun () -> report_progress t ~progress ?total ())
end

module Tool_result = Mcp_sdk.Tool_result

module Server = struct
  (* Define the Eio Promise monad *)
  module Io = struct
    type 'a t = 'a Eio.Promise.t

    let return x =
      let promise, resolver = Eio.Promise.create () in
      Eio.Promise.resolve resolver x;
      promise

    let map f p =
      let promise, resolver = Eio.Promise.create () in
      let result = Eio.Promise.await p in
      Eio.Promise.resolve resolver (f result);
      promise

    let run p = Eio.Promise.await p
  end

  (* Include the generated server *)
  include Mcp_sdk.Make_server (Io)

  (* All types are already included from Make_server *)

  (* Add the to_mcp_server that takes sw for compatibility *)
  let to_mcp_server ~sw:_ t = to_mcp_server t

  (* Run an async server with Eio *)
  let run ~sw ~env:_ t connection =
    let mcp_server = to_mcp_server ~sw t in
    (* Set up MCP logging using common functionality *)
    setup_mcp_logging t mcp_server;
    Mcp_eio.Connection.serve ~sw connection mcp_server
end

(* Helper functions for creating async results *)
let async result =
  let promise, resolver = Eio.Promise.create () in
  Eio.Promise.resolve resolver result;
  promise

let async_ok value = async (Ok value)
let async_error msg = async (Error msg)
