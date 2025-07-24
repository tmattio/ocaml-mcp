(** Validator for MCP _meta field keys.

    This module enforces the key naming rules for the `_meta` field as defined
    in the MCP specification. *)

val validate : Yojson.Safe.t option -> (unit, string) result
(** [validate meta_option] checks if the keys in the given JSON object conform
    to the MCP specification for `_meta` fields.

    @param meta_option The optional `_meta` field from a request or response.
    @return
      [Ok ()] if all keys are valid, or [Error reason] if a validation error
      occurs. *)
