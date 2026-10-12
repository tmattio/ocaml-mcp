type t = Jsont.json
(** Native Jsont values. Yojson conversions exist only for dependency APIs.
    Integers outside [-2^53+1;2^53-1] are rejected instead of rounded. *)

val null : t
val string : string -> t
val bool : bool -> t
val number : float -> t
val int : int -> t
val array : t list -> t
val object_ : (string * t) list -> t
val fields : t -> (string * t) list option
val get_string : t -> string option
val get_array : t -> t list option
val member : string -> t -> t option
val of_yojson : Yojson.Safe.t -> t
val to_yojson : t -> Yojson.Safe.t
val of_basic : Yojson.Basic.t -> t
val to_basic : t -> Yojson.Basic.t
val of_string : string -> t
val to_string : t -> string
val of_jsonrpc : Jsonrpc.Json.t -> t
val to_jsonrpc : t -> Jsonrpc.Json.t
