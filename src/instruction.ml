open Term
open Pattern

type instruction =
  | Declaration of Error.pos * string * term
  | Definition of Error.pos * string * term option * term
  | OpaqueDef of Error.pos * string * term option * term
  | Rules of (Error.pos * (string * term) list * pattern * term) list
  | Eof
