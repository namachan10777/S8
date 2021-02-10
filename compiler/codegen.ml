(* ここはad-hocとカスの実装の塊で、マジで動くというただそれだけでしか無いです *)
(* Regは適当な関数呼び出しに関わりなさそうな汎用レジスタ *)

type opr_t = R of int | M of int | F of int [@@deriving show]

type reg_t = Reg of int [@@deriving show]

type mem_t = Mem of int [@@deriving show]

exception Internal of string

type t =
    | Test of reg_t * mem_t * t list * t list
    | Ldi of reg_t * int
    | Ldb of reg_t * bool
    | Load of reg_t * mem_t
    | Save of mem_t * reg_t
    (* label *)
    | MkClosure of mem_t * string * int * mem_t list * mem_t
    (* reg * mems *)
    | Call of mem_t * reg_t * mem_t list
    | App of mem_t * reg_t * mem_t list
    | CallTop of reg_t * int * mem_t list
    | AppTop of reg_t * int * mem_t list
[@@deriving show]

type insts_t = (string * int * int * t list * mem_t) list [@@deriving show]

let rec vid2stack cnt = function
    | Closure.LetApp (id, _, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.LetBool (id, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.LetInt (id, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.LetClosure (id, _, _, _, _, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.LetCall (id, _, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.Phi (id, _, _) :: remain ->
        (id, M cnt) :: vid2stack (cnt + 1) remain
    | Closure.Test (_, block1, block2) :: remain ->
        let ids1 = vid2stack cnt block1 in
        let ids2 = vid2stack (cnt + List.length ids1) block2 in
        ids1 @ ids2
        @ vid2stack (cnt + List.length ids1 + List.length ids2) remain
    | Closure.End :: _ -> []
    | [] -> []

type stackmap_t = (Types.vid_t * opr_t) list [@@deriving show]

let rec g stackmap =
    let rec lookup id = function
        | (id', stack) :: _ when id = id' -> stack
        | _ :: remain -> lookup id remain
        | [] ->
            Printf.printf "%s in %s\n" (Types.show_vid_t id)
              (show_stackmap_t stackmap) ;
            raise
            @@ Internal (Printf.sprintf "undefined %s" @@ Types.show_vid_t id)
    in
    let lookup_mem id =
        match lookup id stackmap with
        | M m -> Mem m
        | _ -> failwith "mem required"
    in
    function
    | Closure.LetInt (mem, i) :: remain ->
        let blocks, insts = g stackmap remain in
        (blocks, Ldi (Reg 0, i) :: Save (lookup_mem mem, Reg 0) :: insts)
    | Closure.LetBool (mem, b) :: remain ->
        let blocks, insts = g stackmap remain in
        (blocks, Ldb (Reg 0, b) :: Save (lookup_mem mem, Reg 0) :: insts)
    | Closure.LetCall (mem, Types.VidTop f, args) :: remain ->
        let blocks, insts = g stackmap remain in
        ( blocks
        , CallTop (Reg 0, f, List.map lookup_mem args)
          :: Save (lookup_mem mem, Reg 0)
          :: insts )
    | Closure.LetApp (mem, Types.VidTop f, args) :: remain ->
        let blocks, insts = g stackmap remain in
        ( blocks
        , AppTop (Reg 0, f, List.map lookup_mem args)
          :: Save (lookup_mem mem, Reg 0)
          :: insts )
    | Closure.LetCall (mem, f, args) :: remain ->
        let blocks, insts = g stackmap remain in
        ( blocks
        , Load (Reg 1, lookup_mem f)
          :: Call (lookup_mem mem, Reg 1, List.map lookup_mem args)
          :: Save (lookup_mem mem, Reg 0)
          :: insts )
    | Closure.LetApp (mem, f, args) :: remain ->
        let blocks, insts = g stackmap remain in
        ( blocks
        , Load (Reg 1, lookup_mem f)
          :: App (lookup_mem mem, Reg 1, List.map lookup_mem args)
          :: Save (lookup_mem mem, Reg 0)
          :: insts )
    | Closure.LetClosure (mem, args, inner, ret, label, pre_applied) :: remain
      ->
        let args_on_stack = List.mapi (fun i id -> (id, M (1 + i))) args in
        let stackmap_inner =
            args_on_stack @ vid2stack (1 + List.length args_on_stack) inner
        in
        let blocks, inner = g stackmap_inner inner in
        let blocks', insts = g stackmap remain in
        let n_args = List.length args + List.length pre_applied in
        let clos_id = lookup_mem mem in
        let ret_id =
            match lookup ret stackmap_inner with
            | M m -> Mem m
            | _ -> failwith "mem required"
        in
        let insts =
            match pre_applied with
            | [] -> MkClosure (clos_id, label, n_args, [], ret_id) :: insts
            | pre_applied ->
                MkClosure
                  ( clos_id
                  , label
                  , n_args
                  , List.map lookup_mem pre_applied
                  , ret_id )
                :: insts
        in
        ( ((label, n_args, List.length stackmap_inner, inner, ret_id) :: blocks)
          @ blocks'
        , insts )
    | Closure.Test (cond, block1, block2) :: Closure.Phi (ret, r1, r2) :: remain
      ->
        let blocks1, inner1 = g stackmap block1 in
        let blocks2, inner2 = g stackmap block2 in
        let blocks, insts = g stackmap remain in
        let ret = lookup_mem ret in
        let r1 = lookup_mem r1 in
        let r2 = lookup_mem r2 in
        let inner1 = inner1 @ [Load (Reg 0, r1)] in
        let inner2 = inner2 @ [Load (Reg 0, r2)] in
        ( blocks1 @ blocks2 @ blocks
        , Load (Reg 0, lookup_mem cond)
          :: Test (Reg 0, ret, inner1, inner2)
          :: insts )
    | [] -> ([], [])
    | [Closure.End] -> ([], [])
    | x ->
        failwith @@ Printf.sprintf "invalid state %s" @@ Closure.show_inst_t x

let code2reg = function
    | 0 -> Emit.Rax
    | 1 -> Emit.Rbx
    | n -> failwith @@ Printf.sprintf "resister overflow %d" n

let arg_reg = function
    | 0 -> Emit.Rdi
    | 1 -> Emit.Rsi
    | 2 -> Emit.Rdx
    | 3 -> Emit.Rcx
    | 4 -> Emit.R8
    | 5 -> Emit.R9
    | _ -> failwith "too many arguments"

module E = Emit

let prepare_args = []

let cnt = ref 0

let fresh_label () =
    cnt := !cnt + 1 ;
    ".L" ^ string_of_int !cnt

(* クロージャのアドレスはRbxに保存しておくこと *)
let set_args () =
    let app1 = fresh_label () in
    let app2 = fresh_label () in
    let app3 = fresh_label () in
    let app4 = fresh_label () in
    let app5 = fresh_label () in
    [ E.C "関数呼び出し準備"
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 16), E.Reg Rcx))
    ; E.I (E.Cmpq (E.Imm 1, E.Reg Rcx))
    ; E.I (E.Je app1)
    ; E.I (E.Cmpq (E.Imm 2, E.Reg Rcx))
    ; E.I (E.Je app2)
    ; E.I (E.Cmpq (E.Imm 3, E.Reg Rcx))
    ; E.I (E.Je app3)
    ; E.I (E.Cmpq (E.Imm 4, E.Reg Rcx))
    ; E.I (E.Je app4)
    ; E.I (E.Cmpq (E.Imm 5, E.Reg Rcx))
    ; E.I (E.Je app5)
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 64), E.Reg (arg_reg 5)))
    ; E.L app5
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 56), E.Reg (arg_reg 4)))
    ; E.L app4
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 48), E.Reg (arg_reg 3)))
    ; E.L app3
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 40), E.Reg (arg_reg 2)))
    ; E.L app2
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 32), E.Reg (arg_reg 1)))
    ; E.L app1
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 24), E.Reg (arg_reg 0))) ]

let copy_stored_args () =
    let app0 = fresh_label () in
    let app1 = fresh_label () in
    let app2 = fresh_label () in
    let app3 = fresh_label () in
    let app4 = fresh_label () in
    let app5 = fresh_label () in
    [ E.I (E.Movq (E.Ind (E.Rbx, None), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, None)))
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 8), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 8)))
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 16), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 16)))
    ; E.C "引数をコピー"
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 16), E.Reg Rcx))
    ; E.I (E.Cmpq (E.Imm 0, E.Reg Rcx))
    ; E.I (E.Je app0)
    ; E.I (E.Cmpq (E.Imm 1, E.Reg Rcx))
    ; E.I (E.Je app1)
    ; E.I (E.Cmpq (E.Imm 2, E.Reg Rcx))
    ; E.I (E.Je app2)
    ; E.I (E.Cmpq (E.Imm 3, E.Reg Rcx))
    ; E.I (E.Je app3)
    ; E.I (E.Cmpq (E.Imm 4, E.Reg Rcx))
    ; E.I (E.Je app4)
    ; E.I (E.Cmpq (E.Imm 5, E.Reg Rcx))
    ; E.I (E.Je app5)
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 64), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 64)))
    ; E.L app5
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 56), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 56)))
    ; E.L app4
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 48), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 48)))
    ; E.L app3
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 40), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 40)))
    ; E.L app2
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 32), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 32)))
    ; E.L app1
    ; E.I (E.Movq (E.Ind (E.Rbx, Some 24), E.Reg E.Rdi))
    ; E.I (E.Movq (E.Reg E.Rdi, E.Ind (E.Rax, Some 24)))
    ; E.L app0 ]

let rec codegen = function
    | Load (Reg r, Mem m) :: remain ->
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * m)), E.Reg (code2reg r)))
        :: codegen remain
    | Save (Mem m, Reg r) :: remain ->
        E.C "save"
        :: E.I (E.Movq (E.Reg (code2reg r), E.Ind (E.Rbp, Some (-8 * m))))
        :: codegen remain
    | MkClosure (Mem m, label, size, args, Mem ret) :: remain ->
        let alloc_container =
            [ E.C ("mkclosure " ^ label)
            ; E.I (E.Movl (E.Imm (8 * (3 + size)), E.Reg E.Edi))
            ; E.I (E.Call (E.Label "malloc@PLT"))
            ; E.I (E.Leaq (E.IndL (E.Rip, Some label), E.Reg E.Rbx))
            ; E.I (E.Movq (E.Reg E.Rbx, E.Ind (E.Rax, None)))
            ; E.I (E.Movq (E.Imm (8 * (3 + size)), E.Ind (E.Rax, Some 8)))
            ; E.I (E.Movq (E.Imm (List.length args), E.Ind (E.Rax, Some 16)))
            ; E.I (E.Movq (E.Reg E.Rax, E.Ind (E.Rbp, Some (-8 * m)))) ]
        in
        let copy_args =
            List.mapi
              (fun i (Mem m) ->
                [ E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * m)), E.Reg E.Rbx))
                ; E.I (E.Movq (E.Reg E.Rbx, E.Ind (E.Rax, Some (8 * (i + 3)))))
                ])
              args
        in
        alloc_container
        @ [E.C ("mkclosure (copy args)" ^ label)]
        @ List.concat copy_args @ codegen remain
        @ [E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * ret)), E.Reg E.Rax))]
    | Call (ret, Reg f, args) :: remain ->
        let alloc_new_closure =
            [ E.C "コンテナサイズを取得"
            ; E.I (E.Movq (E.Ind (code2reg f, Some 8), E.Reg E.Rdi))
            ; E.I (E.Call (E.Label "malloc@PLT")) ]
        in
        let apply_args =
            [ E.I (E.Movq (E.Reg E.Rax, E.Reg E.Rbx))
            ; E.C "適用された引数の文だけカウンタ加算"
            ; E.I (E.Movq (E.Ind (E.Rbx, Some 16), E.Reg E.Rax))
            ; E.I (E.Movq (E.Imm 8, E.Reg E.Rdx))
            ; E.I (E.Mulq (E.Reg E.Rdx))
            ; E.C "クロージャのアドレスを加算"
            ; E.I (E.Addq (E.Reg (code2reg f), E.Reg E.Rax))
            ; E.C "関数ポインタ+引数カウンタ分加算"
            ; E.I (E.Addq (E.Imm (3 * 8), E.Reg E.Rax)) ]
        in
        let copy_args =
            List.concat
            @@ List.mapi
                 (fun i (Mem m) ->
                   [ E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * m)), E.Reg E.Rdx))
                   ; E.I (E.Movq (E.Reg E.Rdx, E.Ind (E.Rax, Some (8 * i)))) ])
                 args
        in
        let update_arg_n =
            [E.I (E.Addq (E.Imm (List.length args), E.Ind (E.Rbx, Some 16)))]
        in
        let call =
            [ E.C "呼び出し"
            ; E.I (E.Movq (E.Ind (code2reg f, None), E.Reg E.Rax))
            ; E.I (E.Call (E.Reg E.Rax)) ]
        in
        ((E.C "call" :: alloc_new_closure) @ copy_stored_args () @ apply_args)
        @ (E.C "引数をクロージャにコピー" :: copy_args)
        @ update_arg_n @ set_args () @ call @ codegen remain
    | CallTop (Reg r, 0, [Mem lhr; Mem rhr]) :: remain ->
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * lhr)), E.Reg (code2reg r)))
        :: E.I (E.Addq (E.Ind (E.Rbp, Some (-8 * rhr)), E.Reg (code2reg r)))
        :: codegen remain
    | CallTop (Reg r, 1, [Mem lhr; Mem rhr]) :: remain ->
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * lhr)), E.Reg (code2reg r)))
        :: E.I (E.Subq (E.Ind (E.Rbp, Some (-8 * rhr)), E.Reg (code2reg r)))
        :: codegen remain
    (* 実装サボってます。CtorやTupleを比較するために再帰的に比較する必要があるんですが、実装サボってます。 *)
    | CallTop (Reg r, 5, [Mem lhr; Mem rhr]) :: remain ->
        let true_l = fresh_label () in
        let goal_l = fresh_label () in
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * rhr)), E.Reg (code2reg r)))
        :: E.I (E.Subq (E.Ind (E.Rbp, Some (-8 * lhr)), E.Reg (code2reg r)))
        :: E.I (E.Jl true_l)
        :: E.I (E.Movq (E.Imm 0, E.Reg (code2reg r)))
        :: E.I (E.Jmp goal_l)
        :: E.L true_l
        :: E.I (E.Movq (E.Imm 1, E.Reg (code2reg r)))
        :: E.L goal_l
        :: codegen remain
    (* 実装サボってます。CtorやTupleを比較するために再帰的に比較する必要があるんですが、実装サボってます。 *)
    | CallTop (Reg r, 6, [Mem lhr; Mem rhr]) :: remain ->
        let true_l = fresh_label () in
        let goal_l = fresh_label () in
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * lhr)), E.Reg (code2reg r)))
        :: E.I (E.Subq (E.Ind (E.Rbp, Some (-8 * rhr)), E.Reg (code2reg r)))
        :: E.I (E.Jl true_l)
        :: E.I (E.Movq (E.Imm 0, E.Reg (code2reg r)))
        :: E.I (E.Jmp goal_l)
        :: E.L true_l
        :: E.I (E.Movq (E.Imm 1, E.Reg (code2reg r)))
        :: E.L goal_l
        :: codegen remain
    (* 実装サボってます。CtorやTupleを比較するために再帰的に比較する必要があるんですが、実装サボってます。 *)
    | CallTop (Reg r, 7, [Mem lhr; Mem rhr]) :: remain ->
        E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * lhr)), E.Reg (code2reg r)))
        :: E.C "calltop"
        :: E.I (E.Cmpq (E.Reg (code2reg r), E.Ind (E.Rbp, Some (-8 * rhr))))
        :: E.I (E.Sete (E.Reg E.Al))
        :: E.I (E.Movzbq (E.Reg E.Al, E.Reg (code2reg r)))
        :: codegen remain
    | CallTop (Reg r, 15, [Mem arg]) :: remain ->
        E.I (E.Leaq (E.IndL (E.Rip, Some ".print_int_s"), E.Reg E.Rdi))
        :: E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * arg)), E.Reg E.Rsi))
        :: E.I (E.Movl (E.Imm 0, E.Reg E.Eax))
        :: E.I (E.Call (E.Label "printf@PLT")) :: codegen remain
    | Test (Reg r, Mem ret, br1, br2) :: remain ->
        let else_l = fresh_label () in
        let goal_l = fresh_label () in
        E.I (E.Testq (E.Reg (code2reg r), E.Reg (code2reg r)))
        :: E.I (E.Jz else_l) :: codegen br1
        @ [E.I (E.Jmp goal_l)] @ [E.L else_l] @ codegen br2 @ [E.L goal_l]
        @ [E.I (E.Movq (E.Reg E.Rax, E.Ind (E.Rbp, Some (-8 * ret))))]
        @ codegen remain
    | Ldb (Reg r, true) :: remain ->
        E.C (Printf.sprintf "Ldi i")
        :: E.I (E.Movq (E.Imm 1, E.Reg (code2reg r)))
        :: codegen remain
    | Ldb (Reg r, false) :: remain ->
        E.C (Printf.sprintf "Ldi 0")
        :: E.I (E.Movq (E.Imm 0, E.Reg (code2reg r)))
        :: codegen remain
    | Ldi (Reg r, i) :: remain ->
        E.C (Printf.sprintf "Ldi %d" i)
        :: E.I (E.Movq (E.Imm i, E.Reg (code2reg r)))
        :: codegen remain
    | [] -> []
    | ir :: _ -> failwith @@ Printf.sprintf "unsupported ir %s\n" @@ show ir

let gen_blocks clos =
    let stackmap = vid2stack 4 clos in
    let store_return_code = [Ldi (Reg 0, 0); Save (Mem 2, Reg 0)] in
    let blocks, main_inner = g stackmap clos in
    ("main", 2, 4 + List.length stackmap, main_inner @ store_return_code, Mem 2)
    :: blocks

let f clos =
    let blocks = gen_blocks clos in
    let blocks =
        List.map
          (fun (label, n_args, n_vars, codes, Mem ret) ->
            let header =
                [ E.D E.Text
                ; E.D (E.Global label)
                ; E.D (E.Type (label, "function"))
                ; E.L label
                ; E.I (E.Pushq (E.Reg E.Rbp))
                ; E.I (E.Movq (E.Reg E.Rsp, E.Reg E.Rbp))
                ; E.I (E.Subq (E.Imm (8 * n_vars), E.Reg E.Rsp)) ]
            in
            let copy_args =
                List.init n_args (fun i ->
                    E.I
                      (E.Movq
                         (E.Reg (arg_reg i), E.Ind (E.Rbp, Some (-8 * (i + 1))))))
            in
            let footer =
                [ E.I (E.Movq (E.Ind (E.Rbp, Some (-8 * ret)), E.Reg E.Rax))
                ; E.I E.Leave
                ; E.I E.Retq
                ; E.L (fresh_label ())
                ; E.D (E.SizeSub (label, ".", label)) ]
            in
            header @ copy_args @ codegen codes @ footer)
          blocks
        |> List.concat
    in
    let preamble =
        [ E.D (E.File "test.ml")
        ; E.D E.Text
        ; E.D (E.Section (".rodata", None))
        ; E.L ".print_int_s"
        ; E.D (E.Asciz "%lld") ]
    in
    let footer =
        [E.D (E.Section (".note.GNU-stack", Some ("", Some ("progbits", None))))]
    in
    Emit.f @@ preamble @ blocks @ footer
