(** Incremental parser for Server-Sent Events (SSE) streams.

    Used by the HTTP transport to read [text/event-stream] responses from
    Streamable HTTP servers, where a single POST can yield several JSON-RPC
    messages (e.g. progress notifications followed by the final response). *)

type event = {
  name : string option;  (** Value of the [event:] field, if any. *)
  data : string;  (** Concatenated [data:] lines, joined with newlines. *)
}

type t
(** Mutable parser state for one stream. *)

val create : unit -> t

val feed_line : t -> string -> event option
(** [feed_line t line] feeds one line of the stream (without its trailing
    newline; a trailing CR is stripped). Returns [Some event] when a blank
    line completes an event that carries data, [None] otherwise. Events with
    no [data:] lines are discarded, and comment lines (starting with [:])
    are ignored, per the SSE specification. Feed an empty line at EOF to
    flush a final unterminated event. *)
