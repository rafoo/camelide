open Term
open Rule
open Type

let path = ref ""

let loading_modules = ref []

let loaded_modules = ref []

let current_module () = List.hd !loading_modules

(* Register the filename in the lexbuf to obtain useful error messages. *)
let setup_lexbuf filename =
  let out_channel =
    try open_in filename 
    with Sys_error(msg) -> Error.module_error "Cannot open file %s" msg in
  let lexbuf = Lexing.from_channel out_channel in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p
      with Lexing.pos_fname = filename };
  lexbuf

let rec load_dependencies term =
  match term.body with
  | Type | Kind -> ()
  | Var(x) ->
      if not (Scope.is_qualified x) then () else
      let prefix, _ = Scope.unqualify x in
      load_module prefix
  | App(t1, t2) -> load_dependencies t1; load_dependencies t2
  | Lam(x, a, t) -> load_dependencies a; load_dependencies t
  | Pi (x, a, b) -> load_dependencies a; load_dependencies b

and load_dependencies_terms terms =
  List.iter load_dependencies terms

and process_declaration x a =
  load_dependencies a;
  Error.print_verbose 2 "Checking declaration %s..." x;
  let a = Scope.qualify_term a [] in
  check_declaration x a;
  Hashtbl.add declarations (Scope.qualify x) a

and process_rule env left right =
  load_dependencies_terms (left :: right :: (snd (List.split env)));
  let head, _ = extract_spine left in (* To get the name of the rule *)
  Error.print_verbose 2 "Checking rule for %s..." head;
  let env, left, right = Scope.qualify_rule env left right in
  check_rule env left right;
  let _, spine = extract_spine left in (* To get the qualified spine *)
  Hashtbl.add rules (Scope.qualify head) (fst (List.split env), spine, right)

and process_instructions lexbuf =
  let instruction = Parser.toplevel Lexer.token lexbuf in
  match instruction with
    | Declaration(x, a) ->
        process_declaration x a;
        process_instructions lexbuf
    | Rule(env, left, right) ->
        process_rule env left right;
        process_instructions lexbuf
    | Eof -> ()

(* Modules are loaded, parsed, and executed on the fly, as needed. *)
and load_module name =
  if List.mem name !loaded_modules then () else
  if List.mem name !loading_modules
  then Error.module_error "Circular dependency between %s.dk and %s.dk" (current_module ()) name
  else begin
    Error.print_verbose 1 "Loading module %s..." name;
    loading_modules := name :: !loading_modules;
    Scope.push_scope name;
    let filename = Filename.concat !path (name ^ ".dk") in
    let lexbuf = setup_lexbuf filename in
    process_instructions lexbuf;
    Scope.pop_scope ();
    loading_modules := List.tl !loading_modules;
    loaded_modules := name :: !loaded_modules;
    Error.print_verbose 1 "Finished loading %s!" name
  end

let load_file filename =
  if Filename.check_suffix filename ".dk" then () else
  Error.module_error "Invalid file extension %s" filename;
  path := Filename.dirname filename;
  let module_name = Filename.chop_extension (Filename.basename filename) in
  load_module module_name;
  Error.print_verbose 0 "OK!"
