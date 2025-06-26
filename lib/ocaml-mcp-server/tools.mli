(** MCP tool implementations for OCaml development. *)

open Mcp.Types

val all_tools : Tool.t list
(** [all_tools] lists available development tools. *)

val handle_tool_call :
  dune_rpc:Dune_rpc_client.t option ->
  merlin:Merlin_client.t option ->
  Mcp.Request.Tools.Call.params ->
  Mcp.Request.Tools.Call.result
(** [handle_tool_call ~dune_rpc ~merlin params] dispatches tool calls.

    Available tools:
    - dune/build-status: Build progress and diagnostics
    - ocaml/module-signature: Module type information *)
