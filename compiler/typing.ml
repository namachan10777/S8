(* Algorithm W*)

type id_t = Ast.id_t
[@@deriving show]

type pat_t =
    | PVar of string * Types.t
    | PTuple of pat_t list * (Types.t list)
[@@deriving show]

type t =
    | Int of int
    | Bool of bool
    | Var of id_t
    | App of t * t list
    | Let of (pat_t * t) list * t
    | LetRec of (string list * Types.t * t) list * t
    | If of t * t * t
    | Fun of (string * Types.t) list * t * Types.t
    | Tuple of t list * Types.t list
[@@deriving show]

let rec lookup x = function
    | (y, ty) :: remain -> if x = y then ty else lookup x remain
    | _ -> failwith @@ Printf.sprintf "notfound %s" @@ Ast.show_id_t x


let count = ref 0
let init () =
    count := 99

let fresh level =
    count := !count + 1; Types.Unknown (ref @@ ref @@ Types.U (level, !count, None, []))

let rec instantiate level =
    let env = ref [] in
    let lookup i =
        let rec f = function
        | (x, y) :: remain -> if i = x then y else f remain
        | [] ->
            let unk = fresh level in
            env := (i, unk) :: !env;
            unk
        in f !env
    in
    let rec f = function
        | Types.Int -> Types.Int
        | Types.Bool -> Types.Bool
        | Types.Fun (args, ret) -> Types.Fun (List.map f args, f ret)
        | Types.Unknown _ as t -> t
        | Types.Poly i ->
            lookup i
        | Types.Tuple ts ->
            Types.Tuple (List.map f ts)
        | _ -> failwith "instantiate unimplemented"
    in f

let rec occur_check id =
    let rec f = function
    | Types.Int -> ()
    | Types.Bool -> ()
    | Types.Str -> ()
    | Types.Poly _ -> ()
    | Types.Tuple ts -> List.map f ts |> ignore
    | Types.Array t -> f t
    | Types.Higher (t, _) -> f t
    | Types.Ref t -> f t
    | Types.Fun (args, ret) -> List.map f args|>ignore; f ret
    | Types.Unknown u -> begin match ! ! u with
        | Types.U (_, id', None, _) ->
            if id = id'
            then failwith "cyclic type"
            else ()
        | Types.U (_, _, Some t, _) -> f t
    end
    in f

let rec unify a b =
    let unify_unk_and_t u t =
        match !u with
        | Types.U (level, tag, None, refs) ->
            occur_check tag t;
            let refs = u :: refs in
            let u = Types.U (level, tag, Some t, refs) in
            List.map (fun r -> r := u) refs |> ignore;
            t
        | Types.U (level, tag, Some t', refs) ->
            let refs = u :: refs in
            let t = unify t t' in
            let u = Types.U (level, tag, Some t, refs) in
            List.map (fun r -> r := u) refs |> ignore;
            t
    in
    match a, b with
    | Types.Int, Types.Int -> Types.Int
    | Types.Bool, Types.Bool -> Types.Bool
    | Types.Fun ([], _), Types.Fun ([], _) -> failwith "unreachable"
    | Types.Fun ([], r), b ->
        unify r b
    | a, Types.Fun ([], r) ->
        unify r a
    | Types.Fun ([a1], r1), Types.Fun ([a2], r2) ->
        Types.Fun ([unify a1 a2], unify r1 r2)
    | Types.Fun (a1 :: as1, r1), Types.Fun (a2 :: as2, r2) ->
        begin match unify (Types.Fun (as1, r1)) (Types.Fun (as2, r2)) with
        | Types.Fun (as', r) -> Types.Fun ((unify a1 a2) :: as', r)
        | _ -> failwith "cannot unify fun"
        end
    | Types.Tuple ts1, Types.Tuple ts2 ->
        Types.Tuple (Util.zip ts1 ts2 |> List.map (fun (e1, e2) -> unify e1 e2))
    | Types.Unknown u1, Types.Unknown u2 ->
        let unify_u_and_u level tag u1 u2 refs1 refs2 t =
            let refs = u1 :: u2 :: refs1 @ refs2 in
            let u = Types.U (level, tag, t, refs) in
            List.map (fun r -> r := u) refs |> ignore;
            Types.Unknown (ref u1)
        in begin match ! !u1, ! !u2 with
            | Types.U (level, tag, None, refs1), Types.U (level', _, None, refs2) when level < level' ->
                unify_u_and_u level tag !u1 !u2 refs1 refs2 None
            | Types.U (_, _, None, refs1), Types.U (level, tag, None, refs2) ->
                unify_u_and_u level tag !u1 !u2 refs1 refs2 None
            | Types.U (level, tag, Some t, refs1), Types.U (_, _, Some t', refs2) ->
                unify_u_and_u level tag !u1 !u2 refs1 refs2 (Some (unify t t'))
            | Types.U (_, _, None, refs1), Types.U (level, tag, Some t, refs2) ->
                unify_u_and_u level tag !u1 !u2 refs1 refs2 (Some t)
            | Types.U (level, tag, Some t, refs1), Types.U (_, _, None, refs2) ->
                unify_u_and_u level tag !u1 !u2 refs1 refs2 (Some t)
        end
    | Types.Unknown u, t -> unify_unk_and_t !u t
    | t, Types.Unknown u -> unify_unk_and_t !u t
    | a, b -> failwith @@ Printf.sprintf "cannot unify %s, %s" (Types.show a) (Types.show b)

type poly_map_t =
    | Unknown of int
    | Poly of int

let readable global tag =
    let rec f tbl = match tag, tbl with
        | Poly tag, (Poly tag', y) :: remain when tag = tag' ->
            y
        | Unknown tag, (Unknown tag', y) :: remain when tag = tag' ->
            y
        | _, _ :: remain -> f remain
        | (_, []) ->
            global := (tag, List.length !global) :: !global;
            (List.length !global) - 1
    in
        let x = f !global in
        x

let generalize_ty tbl level =
    let rec f = function
    | Types.Int -> Types.Int
    | Types.Bool -> Types.Bool
    | Types.Unknown u as ty ->
        begin match ! !u with
        | Types.U (_, _, Some ty, _) -> f ty
        | Types.U (level', tag, None, _) ->
            if level' > level
            then Types.Poly (readable tbl (Unknown tag))
            else ty
        end
    | Types.Fun (args, ret_ty) ->
        Types.Fun (List.map f args, f ret_ty)
    | Types.Tuple ts ->
        Types.Tuple (List.map f ts)
    | Types.Poly tag ->
        Types.Poly (readable tbl (Poly tag))
    | x -> failwith @@ Printf.sprintf "generalize unimplemented %s" @@ Types.show x
    in f

let rec generalize_pat tbl level =
    let rec f = function
    | PVar (id, ty) -> PVar (id, generalize_ty tbl level ty)
    | PTuple (ps, ty) -> PTuple (List.map f ps, List.map (generalize_ty tbl level) ty)
    in f

let generalize tbl level =
    let rec f = 
    function
    | Int i -> Int i
    | Bool b -> Bool b
    | Var id -> Var id
    | App (g, args) -> App (f g, List.map f args)
    | Fun (args, body, ret_ty) ->
        Fun (
            List.map (fun (arg, ty) -> arg, generalize_ty tbl level ty) args,
            f body,
            generalize_ty tbl level ret_ty
        )
    | Tuple (vals, types) ->
        Tuple (List.map f vals, List.map (generalize_ty tbl level) types)
    | Let (defs, expr) ->
        Let (List.map (fun (pat, def) -> (generalize_pat tbl level pat, f def)) defs, f expr)
    | LetRec (defs, expr) ->
        LetRec (List.map (fun (name, ty, def) -> (name, generalize_ty tbl level ty, f def)) defs, f expr)
    | If (cond, e1, e2) ->
        If (f cond, f e1, f e2)
    in f

type env_t = (id_t * Types.t) list
[@@deriving show]

let rec pat_ty level = function
    | Ast.PVar name ->
        let ty = fresh level in
        [[name], ty], ty, PVar (name, ty)
    | Ast.PTuple ts ->
        let names, tys, ps = Util.unzip3 @@ List.map (pat_ty level) ts in
        List.concat names, Types.Tuple tys, PTuple (ps, tys)
    | _ -> failwith @@ "unsupported pattern"

let rec g env level =
    let (venv, tenv, cenv) = env in
    function
    | Ast.Int i -> Int i, Types.Int
    | Ast.Bool b -> Bool b, Types.Bool
    | Ast.Var id -> Var id, lookup id venv
    | Ast.App (f, args) -> 
        let args, arg_tys = Util.unzip @@ List.map (g env level) args in
        let arg_tys = List.map (instantiate level) arg_tys in
        let f, f_ty = g env level f in
        let f_ty' = Types.Fun (arg_tys, fresh level) in
        let f_ty = instantiate level f_ty in
        let f_ty = unify (instantiate level f_ty) f_ty' in
        begin match f_ty with
        | Types.Fun (params, ret_ty) ->
            if (List.length params) > (List.length args)
            then
                let param_tys = Util.drop (List.length arg_tys) params in
                App (f, args), Types.Fun (param_tys, ret_ty)
            else if (List.length params) = (List.length args)
            then
                App (f, args), ret_ty
            else
                failwith "too much argument"
        | _ -> failwith "unmatched app"
        end
    | Ast.Let ([pat, def], expr) ->
        let def, def_ty = g env (level + 1) def in
        let pat_vars, pat_ty, pat = pat_ty (level + 1) pat in
        unify pat_ty def_ty |> ignore;
        let tbl = ref [] in
        let def, def_ty = generalize tbl level def, generalize_ty tbl level def_ty in
        let pat, pat_ty = generalize_pat tbl level pat, generalize_ty tbl level pat_ty in
        let pat_vars = List.map (fun (name, ty) -> name, generalize_ty tbl level ty) pat_vars in
        let expr, ty = g (pat_vars @ venv, tenv, cenv) level expr in
        Let ([pat, def], expr), ty
    | Ast.LetRec ([name, def], expr) ->
        let env = (name, fresh (level+1)) :: venv, tenv, cenv in
        let def, def_ty = g env (level + 1) def in
        let tbl = ref [] in
        let def, def_ty = generalize tbl level def, generalize_ty tbl level def_ty in
        let expr, ty = g env level expr in
        LetRec ([name, def_ty, def], expr), ty
    | Ast.Fun (args, body) ->
        let args = List.map (fun arg -> arg, fresh level) args in
        let arg_as_vars = List.map (fun (arg, ty) -> [arg], ty) args in
        let body, body_ty = g (arg_as_vars @ venv, tenv, cenv) level body in
        Fun (args, body, body_ty), Types.Fun (List.map snd args, body_ty)
    | Ast.Tuple tp ->
        let elems, types = Util.unzip @@ List.map (g env level) tp in
        Tuple (elems, types), Types.Tuple types
    | Ast.If (cond, e1, e2) ->
        let cond, cond_ty = g env level cond in
        unify cond_ty Types.Bool |> ignore;
        let e1, e1_ty = g env level e1 in
        let e2, e2_ty = g env level e2 in
        If (cond, e1, e2), unify e1_ty e2_ty
    | t -> failwith @@ Printf.sprintf "unimplemented: %s" @@ Ast.show t

let f ast =
    fst @@ g (
        Types.pervasive_vals,
        Types.pervasive_types,
        Types.pervasive_ctors
    ) 0 ast
