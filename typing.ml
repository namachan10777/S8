type ty =
    | TNever
    | TInt
    | TBool
    | TStr
    | TFun of ty * ty
    | TTuple of ty list
    | Poly of int
    | TyVar of int (* arrayに対するindexとして持つ *)
    | TVariant of ty list * Id.t
[@@deriving show]
and ty_var_t = Just of ty * int list | Unknown of int * int * int list [@@deriving show]

(* 型推論を実装する際に問題となるのは不明な型をどう扱うかである。
 * 不明ではあってもunifyによって不明なまま単一化されることがありうる。
 * ナイーブにrefで実装するとこの単一となる制約を守りきれない（無限段必要になる）
 * 一つの解決策として、「自分自身を含む同一制約を持つ全てのの不明な方への参照のリスト」を保持し、
 * コレを用いて書き換えるという方法がある。ただしこれは循環参照を作成するためppx_derivingで表示できず=で比較も出来ない。
 * 双方ともに単純な深さ優先でポインタをたどるためである。
 * もう一つの解決策としてArrayを使う方法がある。これは実質的にはRAMのエミュレートであるが、
 * 実体の場所が自明にグローバルなのでバグを起こしづらい。また=やppx_deriving.showがそのまま使えるのが利点である。
 * 今回は後者を採用している。
 *)

exception UnifyError
exception TypingError

type pat_t =
    | PInt of int * Lex.pos_t
    | PBool of bool * Lex.pos_t
    | PVar of Id.t * ty * Lex.pos_t
    | PTuple of (pat_t * ty) list * Lex.pos_t
    | As of pat_t list * ty * Lex.pos_t
    | Or of pat_t * pat_t list * ty * Lex.pos_t
    | PCtorApp of Id.t * (pat_t * ty) list * ty * Lex.pos_t

type tydef_t =
    | Variant of (Id.t * Lex.pos_t * Types.t list) list
    | Alias of Types.t

type t =
    | Never
    | Int of int * Lex.pos_t
    | Bool of bool * Lex.pos_t
    | Var of Id.t * ty * Lex.pos_t
    | CtorApp of Id.t * Lex.pos_t * (t * ty) list * ty
    | Tuple of (t * ty) list * Lex.pos_t
    | If of t * t * t * ty * Lex.pos_t
    | Let of (pat_t * Lex.pos_t * (t * ty)) list * (t * ty) * bool
    | LetRec of (Id.t * Lex.pos_t * (t * ty)) list * (t * ty) * bool
    | Fun of (Id.t * ty) * (t * ty) * Lex.pos_t
    | Match of (t * ty) * ((pat_t * ty) * Lex.pos_t * t * (t * ty)) list
    | App of (t * ty) * (t * ty) * Lex.pos_t
    | Type of (Id.t * Lex.pos_t * (string * Lex.pos_t) list * tydef_t) list * (t * ty)

let store = ref @@ Array.init 2 (fun i -> Unknown (0, i, [i]))
type tenv_t = ty_var_t array [@@deriving show]

let count = ref 0

let init () =
    store := Array.init 2 (fun i -> Unknown (0, i, [i]));
    count := 0

let fresh level =
    let arr_len = Array.length !store in
    if !count >= arr_len then (
      store :=
        Array.concat
          [!store; Array.init arr_len (fun i -> Unknown (0, i+arr_len, [i + arr_len]))] ;
      let idx = !count in
      count := 1 + !count ;
      !store.(idx) <- Unknown(level, idx, [idx]);
      TyVar idx )
    else (
      let idx = !count in
      count := 1 + !count ;
      !store.(idx) <- Unknown(level, idx, [idx]);
      TyVar idx)

let rec unify t1 t2 = match t1, t2 with
    | TyVar v1, TyVar v2 -> begin match !store.(v1), !store.(v2) with
        | Unknown (level1, tag, l1), Unknown (level2, _, l2) when level1 < level2 ->
            let l = l1 @ l2 in
            List.map (fun i -> !store.(i) <- Unknown (level1, tag, l)) l |> ignore
        | Unknown (level1, _, l1), Unknown (level2, tag, l2) ->
            let l = l1 @ l2 in
            List.map (fun i -> !store.(i) <- Unknown (level2, tag, l)) l |> ignore
        | Unknown (_, _, l1), Just (ty, l2) ->
            let l = l1 @ l2 in
            List.map (fun i -> !store.(i) <- Just (ty, l)) l |> ignore
        | Just (ty, l1), Unknown (_, _, l2) ->
            let l = l1 @ l2 in
            List.map (fun i -> !store.(i) <- Just (ty, l)) l |> ignore
        | Just (ty1, l1), Just (ty2, l2) ->
            unify ty1 ty2;
            let l = l1 @ l2 in
            List.map (fun i -> !store.(i) <- Just (ty1, l)) l |> ignore
    end
    | TyVar v, ty -> begin match !store.(v) with
        | Unknown (_, _, l) ->
            List.map (fun i -> !store.(i) <- Just (ty, l)) l |> ignore
        | Just (ty', l) -> unify ty ty'
    end
    | ty, TyVar v -> begin match !store.(v) with
        | Unknown (_, _, l) ->
            List.map (fun i -> !store.(i) <- Just (ty, l)) l |> ignore
        | Just (ty', l) -> unify ty ty'
    end
    | TInt, TInt -> ()
    | TBool, TBool -> ()
    | TStr, TStr -> ()
    | Poly _, _ -> failwith "uninstantiate poly type"
    |  _, Poly _ -> failwith "uninstantiate poly type"
    | TTuple ts, TTuple ts' ->
        Util.zip ts ts'
        |> List.map (fun (t1, t2) -> unify t1 t2)
        |> ignore
    | TFun (arg1, ret1), TFun (arg2, ret2) ->
        unify arg1 arg2;
        unify ret1 ret2
    | TVariant (tys1, id1), TVariant (tys2, id2) ->
        if id1 <> id2
        then raise UnifyError
        else
            Util.zip tys1 tys2
            |> List.map (fun (t1, t2) -> unify t1 t2)
            |> ignore
    | _, _ -> raise UnifyError


(* レベルベースの型推論[1]の簡単な概略を述べる。
 * ナイーブに新しい変数に不明な型を割り付けてunifyしていくと本来多相性を持つ型であっても単相に推論されうる。
 * そのため何らかの方法で多相な部分を見極め、そこを多相型に変換し、unifyに使う際は多相型から不明な型に再び変換する操作が必要となる。
 * 不明な型を多相型に変換するのがgeneralize（一般化）であり、逆がinstantiate（和訳知らぬ）である。
 * ここではletをキーとして操作するlevelを使ってgeneralizeを行う。
 * letの定義に入る度にlevelを1つインクリメントし、抜ける度に1つデクリメントして
 * そのデクリメントしたレベルより高いレベルを持つ不明な変数を全て一般化する。（レベルの低い不明な型はそのまま）
 * そしてinstantiateではその時のlevelで全ての多相型を不明な型に変換する。
 * 不明な型と不明な型のunifyの際はレベルが低い方に合わせ単相に寄せる。
 * [1] Rémy, Didier. Extension of ML Type System with a Sorted Equation Theory on Types. 1992.
 *)
let rec inst_ty env =
    let (level, tbl) = env in
    function
    | TInt -> TInt
    | TBool -> TBool
    | TNever -> TNever
    | TStr -> TStr
    | TFun (f, arg) -> TFun (inst_ty env f, inst_ty env arg)
    | TTuple tys -> TTuple (List.map (inst_ty env) tys)
    | Poly tag -> begin match Tbl.lookup_mut tag tbl with
        | Some u -> u
        | None ->
            let u = fresh level in 
            Tbl.push_mut tag u tbl;
            u
    end
    | TyVar i -> TyVar i
    | TVariant (args, id) -> TVariant (List.map (inst_ty env) args, id)

let rec inst_pat env = function
    | PInt (i, p) -> PInt (i, p)
    | PBool (b, p) -> PBool (b, p)
    | PVar (id, ty, p) -> PVar (id, ty, p)
    | PTuple (pats, p) -> PTuple (List.map (fun (pat, ty) -> inst_pat env pat, inst_ty env ty) pats, p)
    | As (pats, ty, p) -> As (List.map (inst_pat env) pats, inst_ty env ty, p)
    | Or (pat, pats, ty, p) -> Or (inst_pat env pat, List.map (inst_pat env) pats, inst_ty env ty, p)
    | PCtorApp (id, args, ty, p) -> PCtorApp (id, List.map (fun (pat, ty) -> inst_pat env pat, inst_ty env ty) args, inst_ty env ty, p)

let rec inst env = function
    | Never -> Never
    | Int (i, p) -> Int (i, p)
    | Bool (b, p) -> Bool (b, p)
    | Var (id, ty, p) -> Var (id, inst_ty env ty, p)
    | If (c, t, e, ty, p) -> If (inst env c, inst env t, inst env e, inst_ty env ty, p)
    | Fun ((arg, arg_ty), (body, body_ty), p) ->
        Fun ((arg, inst_ty env arg_ty), (inst env body, inst_ty env body_ty), p)
    | Tuple (es, p) -> Tuple (List.map (fun (e, ty) -> inst env e, inst_ty env ty) es, p)
    | App ((f, f_ty), (arg, arg_ty), p) -> App ((inst env f, inst_ty env f_ty), (inst env arg, inst_ty env arg_ty), p)
    | CtorApp (id, p, args, ty) ->
        CtorApp (id, p, List.map (fun (arg, arg_ty) -> inst env arg, inst_ty env arg_ty) args, inst_ty env ty)
    | Let (defs, (e, ty), is_top) ->
        Let (
            List.map (fun (pat, p, (def, def_ty)) -> inst_pat env pat, p, (inst env def, inst_ty env def_ty)) defs,
            (inst env e, inst_ty env ty), is_top
        )
    | LetRec (defs, (e, ty), is_top) ->
        LetRec(
            List.map (fun (id, p, (def, def_ty)) -> id, p, (inst env def, inst_ty env def_ty)) defs,
            (inst env e, inst_ty env ty), is_top
        )
    | Match ((target, target_ty), arms) ->
        Match (
            (inst env target, inst_ty env target_ty),
            List.map (fun ((pat, pat_ty), p, guard, (e, ty)) -> ((inst_pat env pat, inst_ty env pat_ty), p, inst env guard, (inst env e, inst_ty env ty))) arms
        )
    | Type (defs, (e, ty)) -> Type (defs, (e, ty))

let rec gen_ty env =
    let (level, tbl) = env in
    function
    | TInt -> TInt
    | TBool -> TBool
    | TNever -> TNever
    | TStr -> TStr
    | TFun (f, arg) -> TFun (gen_ty env f, gen_ty env arg)
    | TTuple tys -> TTuple (List.map (gen_ty env) tys)
    | Poly tag -> Poly tag
    | TyVar i -> begin match !store.(i) with
        | Unknown (level', tag, _) when level' > level ->
            Tbl.lookup_mut_or tag tbl (Poly tag)
        | Unknown _ -> TyVar i
        | Just (ty, _) -> gen_ty env ty
    end
    | TVariant (args, id) -> TVariant (List.map (gen_ty env) args, id)

let rec gen_pat env = function
    | PInt (i, p) -> PInt (i, p)
    | PBool (b, p) -> PBool (b, p)
    | PVar (id, ty, p) -> PVar (id, ty, p)
    | PTuple (pats, p) -> PTuple (List.map (fun (pat, ty) -> gen_pat env pat, gen_ty env ty) pats, p)
    | As (pats, ty, p) -> As (List.map (gen_pat env) pats, gen_ty env ty, p)
    | Or (pat, pats, ty, p) -> Or (gen_pat env pat, List.map (gen_pat env) pats, gen_ty env ty, p)
    | PCtorApp (id, args, ty, p) -> PCtorApp (id, List.map (fun (pat, ty) -> gen_pat env pat, gen_ty env ty) args, gen_ty env ty, p)

let rec gen env = function
    | Never -> Never
    | Int (i, p) -> Int (i, p)
    | Bool (b, p) -> Bool (b, p)
    | Var (id, ty, p) -> Var (id, gen_ty env ty, p)
    | If (c, t, e, ty, p) -> If (gen env c, gen env t, gen env e, gen_ty env ty, p)
    | Fun ((arg, arg_ty), (body, body_ty), p) ->
        Fun ((arg, gen_ty env arg_ty), (gen env body, gen_ty env body_ty), p)
    | Tuple (es, p) -> Tuple (List.map (fun (e, ty) -> gen env e, gen_ty env ty) es, p)
    | App ((f, f_ty), (arg, arg_ty), p) -> App ((gen env f, gen_ty env f_ty), (gen env arg, gen_ty env arg_ty), p)
    | CtorApp (id, p, args, ty) ->
        CtorApp (id, p, List.map (fun (arg, arg_ty) -> gen env arg, gen_ty env arg_ty) args, gen_ty env ty)
    | Let (defs, (e, ty), is_top) ->
        Let (
            List.map (fun (pat, p, (def, def_ty)) -> gen_pat env pat, p, (gen env def, gen_ty env def_ty)) defs,
            (gen env e, gen_ty env ty), is_top
        )
    | LetRec (defs, (e, ty), is_top) ->
        LetRec(
            List.map (fun (id, p, (def, def_ty)) -> id, p, (gen env def, gen_ty env def_ty)) defs,
            (gen env e, gen_ty env ty), is_top
        )
    | Match ((target, target_ty), arms) ->
        Match (
            (gen env target, gen_ty env target_ty),
            List.map (fun ((pat, pat_ty), p, guard, (e, ty)) -> ((gen_pat env pat, gen_ty env pat_ty), p, gen env guard, (gen env e, gen_ty env ty))) arms
        )
    | Type (defs, (e, ty)) -> Type (defs, (e, ty))


let rec f level env =
    let venv, cenv, tenv = env in
    function
    | Ast.Never -> TNever, Never
    | Ast.Int (i, p) -> TInt, Int (i, p)
    | Ast.Bool (b, p) -> TBool, Bool (b, p)
    | Ast.Var (id, p) ->
        let ty = Tbl.lookup id venv |> Tbl.expect "internal error" in
        ty, Var (id, ty, p)
    | Ast.Fun (arg, body, p) ->
        let u = fresh level in
        let venv = Tbl.push arg u venv in
        let body_ty, body = f level (venv, cenv, tenv) body in
        TFun(u, body_ty), Fun((arg, u), (body, body_ty), p)
    | Ast.If (cond_e, then_e, else_e, p) ->
        let cond_ty, cond_e = f level env cond_e in
        let then_ty, then_e = f level env then_e in
        let else_ty, else_e = f level env else_e in
        unify cond_ty TBool;
        unify then_ty else_ty;
        then_ty, If (cond_e, then_e, else_e, then_ty, p)
    | Ast.App (g, arg, p) ->
        let g_ty, g = f level env g in
        let arg_ty, arg = f level env arg in
        unify (TFun (arg_ty, fresh level)) g_ty;
        begin match g_ty with
        | TyVar idx -> begin match !store.(idx) with
            | Just (TFun (_, ret_ty), _) -> ret_ty, App ((g, g_ty), (arg, arg_ty), p)
            | _ -> raise TypingError
            end
        | TFun (_, ret_ty) -> ret_ty, App ((g, g_ty), (arg, arg_ty), p)
        | _ -> raise TypingError
        end
    | Ast.Tuple (es, p) ->
        let tys, es = Util.unzip @@ List.map (f level env) es in
        TTuple tys, Tuple (Util.zip es tys, p)
    | _ -> failwith "unimplemented"
