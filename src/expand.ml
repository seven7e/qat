open Ast;;
open Macro;;
open Earley;;
module DA = DynArray;;
module StrMap = Util.StrMap;;

type ('m, 't) macro_manager = {
    prcdn: 'm precedences; (* macro precedence hierarchy *)
    gram: 't grammar;
    rules_for_macro: (int, int) Hashtbl.t }
;;

let start_symbol = "E";;

let create_macro_manager () :(macro_elem, Ast.ast) macro_manager =
    {prcdn=make_precedences ();
    gram=g start_symbol [| |];
    rules_for_macro=Hashtbl.create 100}
;;

let v s = Variable s;;
let ls s = Literal (Id s);;
let lo s = Literal (Op s);;

let show_macro_manager mmngr :string =
    "========= Macros =========\n"
    ^ str_of_precedences mmngr.prcdn
    ^ "\n========== Grammar ==========\n"
    ^ str_of_grammar mmngr.gram
    ^ "\n========== Macro rule indices ==========\n"
    ^ let keys = List.sort
            (fun a b -> a - b)
            (Util.hashtbl_keys mmngr.rules_for_macro) in
        let f k = string_of_int k ^ ":" ^ string_of_int
            (Hashtbl.find mmngr.rules_for_macro k) in
        String.concat ", " (List.map f keys)

;;

let add_macro_between mmngr =
    Macro.add_macro_between mmngr.prcdn
;;

let add_macro_equals mmngr =
    Macro.add_macro_equals mmngr.prcdn
;;

let get_macro mmngr =
    Macro.get_macro mmngr.prcdn
;;

let get_macro_of_rule mmngr i =
    Macro.get_macro mmngr.prcdn (Hashtbl.find mmngr.rules_for_macro i)
;;

let is_macro mmngr i :bool =
    (*i < DA.length mmngr.macros*)
    Hashtbl.mem mmngr.rules_for_macro i
;;

let macro_to_op_fix mcr :(ast symbol) array =
    let f m :(ast symbol) =
        match m with
        | Atom a ->
                (match a with
                | Literal lit -> t (str_of_token lit) (fun x -> x = Atom lit)
                | Variable v -> n start_symbol)
        | NodeList _ -> raise (MacroErr
                "Not support list as macro pattern element")
    in
    match mcr.pattern with
    | Atom a -> raise (MacroErr "Macro pattern should be a list")
    | NodeList el -> let sub =
        (let arr = Array.of_list el in
        match mcr.fix with
        | Closed -> arr
        | Infix _ -> Array.sub arr 1 (Array.length arr - 2)
        | Prefix -> Array.sub arr 0 (Array.length arr - 1)
        | Postfix -> Array.sub arr 1 (Array.length arr - 1))
        in
        Array.map f sub
;;

let ast_terminal_arr = [| t "e" (fun x -> true) |];;

let add_pgroup_rules mmngr p :unit =
    let g = mmngr.gram in
    let get_p_sym prefix = prefix ^ string_of_int p in
    let get_p_hat p = "P" ^ string_of_int p in
    let p_hat = get_p_hat p in
    let p_up    = get_p_sym "U" in
    let p_right = get_p_sym "R" in
    let p_left  = get_p_sym "L" in
    let p_up_arr    = [| n p_up |]    in
    let p_right_arr = [| n p_right |] in
    let p_left_arr  = [| n p_left |]  in
    let p_sym_added = Hashtbl.create 5 in
    let add_rule_g lhs rhs macro_idx :unit =
        add_rule g (r lhs rhs);
        if macro_idx >= 0 then
            let rule_idx = num_rules g - 1 in
            Hashtbl.add mmngr.rules_for_macro rule_idx macro_idx
    in
    let add_rule_p_up () :unit =
        (*let p_up_added = (Hashtbl.mem p_sym_added p_up) in*)
        (*Printf.printf "p up added: %d %s\n" p (string_of_bool p_up_added);*)
        if not (Hashtbl.mem p_sym_added p_up) then begin
            List.iter
                (function
                    | 0 -> add_rule_g p_up ast_terminal_arr (-1)
                    | j -> add_rule_g p_up [| n (get_p_hat j) |] (-1))
                (get_higher_pgroups mmngr.prcdn p);
            Hashtbl.add p_sym_added p_up true
        end
    in
    let add_rule_p_hat sym :unit =
        if not (Hashtbl.mem p_sym_added sym) then begin
            add_rule_g p_hat [| n sym |] (-1);
            Hashtbl.add p_sym_added sym true
        end
    in
    let add_macro_rule imcr :unit =
        let mcr = Macro.get_macro mmngr.prcdn imcr in
        let op_fix = macro_to_op_fix mcr in
        (*let str_i = string_of_int (get_macro_index mmngr.prcdn mcr.id) in*)
        match mcr.fix with
        | Closed -> add_rule_g p_hat op_fix imcr
        | Infix Non ->
                (let rhs = Array.concat [ p_up_arr; op_fix; p_up_arr ] in
                add_rule_g p_hat rhs imcr;
                add_rule_p_up ())
        | Prefix | Infix Right -> (
                let arr = match mcr.fix with
                    | Prefix -> op_fix
                    | Infix Right -> Array.append p_up_arr op_fix
                    | _ -> assert false
                in
                add_rule_p_hat p_right;
                add_rule_g p_right (Array.append arr p_right_arr) imcr;
                add_rule_g p_right (Array.append arr p_up_arr) imcr;
                add_rule_p_up ())
        | Postfix | Infix Left -> (
                let arr = match mcr.fix with
                    | Postfix -> op_fix
                    | Infix Left -> Array.append op_fix p_up_arr
                    | _ -> assert false
                in
                add_rule_p_hat p_left;
                add_rule_g p_left (Array.append p_left_arr arr) imcr;
                add_rule_g p_left (Array.append p_up_arr arr) imcr;
                add_rule_p_up ())
    in
    add_rule_g start_symbol [| n p_hat |] (-1);
    DA.iter add_macro_rule (get_macro_indices_in_pgroup mmngr.prcdn p)
;;

let build_grammar mmngr :unit =
    let f i :unit =
        (*Printf.printf "dfs: %d\n" i;*)
        match i with
        (*precedence 0 is a special one for ast terminal*)
        | 0 -> add_rule mmngr.gram (r start_symbol ast_terminal_arr)
        | _ -> add_pgroup_rules mmngr i
    in
    (*add_rule mmngr.gram (r start_symbol [| t (fun x -> true) |]);*)
    Macro.iter_pgroup f mmngr.prcdn;
    ()
;;

let rec parse_tree_to_ast (tree :'a parse_tree) :ast =
    match tree with
    | Leaf lf -> lf
    | Tree (i, arr) ->
            NodeList (Array.to_list (Array.map parse_tree_to_ast arr))
;;

let rec simplify_parse_tree mmngr ptree :'a parse_tree =
    let f = simplify_parse_tree mmngr in
    match ptree with
    | (Leaf _) as lf -> lf
    | Tree (i, arr) ->
            if is_macro mmngr i then
                Tree (i, (Array.map f arr))
            else if Array.length arr <> 1 then
                raise (MacroErr
                "Grammar rules not for a macro should have a length-one rhs")
            else
                f (Array.get arr 0)
;;

let str_of_ast_array arr =
    "[" ^ (Util.joina ", " (Array.map str_of_ast arr)) ^ "]"
;;

let parse_pattern_raw mmngr exp :'a parse_tree =
    let arr = match exp with
        | Atom a -> raise (MacroErr "Input should be a list, not an atom")
        | NodeList el -> Array.of_list el
    in
    (*Util.println (str_of_items str_of_ast mmngr.gram (earley_match mmngr.gram arr));*)
    try parse mmngr.gram arr
    with EarleyErr i ->
        let ierr = i - 1 in
        raise (MacroErr ("macro expanding error at token " ^ string_of_int i
            ^ ": "
            ^ str_of_ast_array (Array.sub arr ierr (Array.length arr - ierr))))
;;

let parse_pattern mmngr exp :'a parse_tree =
    simplify_parse_tree mmngr (parse_pattern_raw mmngr exp)
;;

let rec extract_vars_list (patt_list :macro_ast list)
                      (ast_list :ast list)
                      :ast StrMap.t =
    match patt_list, ast_list with
    | [], [] -> StrMap.empty
    | p::ps, e::es ->
            let mmap_first = extract_vars p e in
            let mmap_rest = extract_vars_list ps es in
            Util.merge_str_map mmap_first mmap_rest
    | _ -> raise (MacroErr "")
and extract_vars_atom (patt :macro_elem) (exp :ast) :ast StrMap.t =
    match patt, exp with
    | Literal lit, Atom a when lit = a -> StrMap.empty
    | Variable v, _ -> StrMap.add v exp StrMap.empty
    | _ -> raise (MacroErr "")
and extract_vars (pattern :macro_ast) (exp :ast) :ast StrMap.t =
    match pattern, exp with
    | Atom a, e -> extract_vars_atom a e
    (*TODO: change to foldr *)
    | NodeList pl,  NodeList el -> extract_vars_list pl el
    | _ -> raise (MacroErr "")
;;

let rec substitute_vars (vars :ast StrMap.t) (body :macro_ast) :ast =
    match body with
    | Atom a ->
            (match a with
            | Literal lit -> Atom lit
            | Variable v -> StrMap.find v vars)
    | NodeList ml -> NodeList (List.map (substitute_vars vars) ml)
;;

let expand_macro (mcr :'m macro) (exp :ast) :ast =
    let vars = extract_vars mcr.pattern exp in
    (*Printf.printf "var mapping: %s\n" (Util.str_of_strmap str_of_ast vars);*)
    substitute_vars vars mcr.body
;;

let rec expand_non_macro mmngr i arr :ast =
    if Array.length arr <> 1 then
        raise (MacroErr
            "Grammar rules not for a macro should have a length-one rhs")
    else
        expand_parse_tree mmngr (Array.get arr 0)
and expand_rule mmngr i arr :ast =
    if is_macro mmngr i then
        let f = expand_parse_tree mmngr in
        expand_macro (get_macro_of_rule mmngr i)
                (* expand inner first, i.e. depth-first *)
                (NodeList (Array.to_list (Array.map f arr)))
    else
        expand_non_macro mmngr i arr
and expand_parse_tree mmngr ptree :ast =
    match ptree with
    | Leaf lf -> lf
    | Tree (i, arr) -> expand_rule mmngr i arr
;;

let expand_one_level mmngr stmt =
    let tree = parse_pattern mmngr stmt in
    expand_parse_tree mmngr tree
;;

let compute_fixity assoc_stmt pattern_stmt =
;;

let ast_to_m_ast stmt :macro_ast =
    let trans_stmt e head_rev =
        match e with
        | [] -> head_rev
        | Atom (Op "?")::Atom (Id opd)::rest ->
            trans_stmt rest (Variable opd::head_rev)
        | Atom opr::rest ->
            trans_stmt rest (Literal opr::head_rev)
        | _ -> raise (MacroErr "MACRO parameter invalid")
    in
    match stmt with
    | NodeList nl -> List.rev (trans_stmt nl head [])
    | _ -> raise (MacroErr "MACRO pattern/body should be a statement")
;;

let define_macro mmngr
        (assoc_stmt :ast option)
        (preced_stmt :ast)
        (pattern_stmt :ast)
        (body_stmt :ast) :unit =
    let fix = compute_fixity assoc_stmt pattern_stmt in
    let pre = compute_precendence preced_stmt in
    let m = new_macro (ast_to_m_ast pattern_stmt) (ast_to_m_ast body_stmt)
    in
    add_macro mmngr m
;;

let rec expand mmngr (stmt :ast) :ast =
    match stmt with
    | (Atom _) as a -> a
    | NodeList (Atom (Id "defmacro")::tail) -> (match tail with
        | [preced_stmt; pattern_stmt; body_stmt] ->
            define_macro tail; NodeList []
        | [assoc_stmt; preced_stmt; pattern_stmt; body_stmt] ->
            define_macro tail; NodeList []
        | raise MacroErr "DEFMACRO: invalid syntax")
    | NodeList nl -> let deep_expanded =
        NodeList (List.map (expand mmngr) nl) in
        try
            expand_one_level mmngr deep_expanded
        with
            | MacroErr _ -> stmt
;;
