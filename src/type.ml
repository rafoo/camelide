open Term
open Pattern
open Rule
open Printer

let use_coc = ref false

let product_rule s1 s2 pos =
  let s1 = normalize s1 in
  let s2 = normalize s2 in
  match s1.body, s2.body with
  | Type, Type -> s2
  | Type, Kind -> s2
  | Kind, Type when !use_coc -> s2
  | Kind, Kind when !use_coc -> s2
  | _ -> Error.type_error pos "This sort of product is not allowed (%a, %a)" print_term s1 print_term s2

(* The type-checking/type-inference algorithm of lambda-Pi-modulo. *)
let rec type_of env term =
  match term.body with
  | Type -> term_kind
  | Kind -> Error.type_error term.pos "Cannot type Kind"
  | Var(x) ->
      begin try List.assoc x env with Not_found ->
      begin try Hashtbl.find declarations x with Not_found ->
      Error.type_error term.pos "Unbound variable %s" x end end
  | App(t1, t2) ->
      let a1 = normalize (type_of env t1) in
      begin match a1.body with
      | Pi(x, a, b) -> check_type env t2 a; if x = "" then b else normalize (subst [x, t2] b)
      | _ -> Error.type_error t1.pos "This term has type\n %a\nbut a product type was expected" print_term a1 end
  | Lam(x, a, t) ->
      let s1 = type_of env a in
      let b  = type_of ((x, a) :: env) t in
      let s2 = type_of ((x, a) :: env) b in
      let _  = product_rule s1 s2 term.pos in
(*      let _ = type_of env a in*)
(*      let b = type_of ((x, a) :: env) t in*)
      new_term (Pi(x, a, b))
  | Pi(x, a, b) ->
      let s1 = type_of env a in
      let s2 = type_of ((x, a) :: env) b in
      product_rule s1 s2 term.pos

and check_type env term a =
  let b = type_of env term in
  if alpha_equiv (normalize a) (normalize b) then () else
  Error.type_error term.pos "This term has type\n %a\nbut a term was expected of type\n %a" print_term b print_term a

let check_sort env term =
  let s = normalize (type_of env term) in
  match s.body with
  | Type | Kind -> ()
  | _ -> Error.type_error term.pos "This term has an invalid sort %a " print_term s

let check_declaration pos x a =
  if is_declared (Scope.qualify x)
    then Error.type_error pos "Declaration %s is already defined" x else
  check_sort [] a

let check_definition pos x a t =
  check_declaration pos x a;
  check_type [] t a

(* Check that the environment env is well-formed. The order of the environment
   is reversed during the process. *)
let check_env env =
  let rec check_env checked env =
    match env with
    | [] -> checked
    | (x, a) :: t ->
        check_sort checked a;
        check_env ((x, a) :: checked) t
  in check_env [] env

let check_rule_fv left right =
  let fvl = free_pvars left in
  let fvr = free_vars right in
  try
    let x = List.find (fun x -> not (List.mem x fvl)) fvr in
    Error.pattern_error right.pos "The free variables %s must appear on the left side of the rule" x
  with Not_found -> ()

let check_rule pos env left right =
  check_pattern env left;
  check_rule_fv left right;
  let env = check_env env in (* Reverses the order of env. *)
  let a = type_of env (term_of_pattern left) in
  check_type env right a
