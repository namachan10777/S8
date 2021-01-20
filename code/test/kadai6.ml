open OUnit2
open S8.K6ast
open S8.K6top

let parse_str _ =
    let ast = parse_repl_string "\"hoge\\\"fuga\"" in
    assert_equal ast (StrLit "hoge\\\"fuga")

let parse_add1 _ =
    let ast = parse_repl_string "1+2+3" in
    assert_equal ast (Add (Add (IntLit 1, IntLit 2), IntLit 3))

let parse_add2 _ =
    let ast = parse_repl_string "1+-2" in
    assert_equal ast (Add (IntLit 1, Sub (IntLit 0, IntLit 2)))

let eval_add _ =
    let value = eval_string "1+2+3" in
    assert_equal value (IntVal 6)

let parse_mod _ =
    let ast = parse_repl_string "3 mod 2" in
    assert_equal ast (Mod (IntLit 3, IntLit 2))

let eval_mod _ =
    let ast = eval_string "3 mod 2" in
    assert_equal ast (IntVal 1)

let parse_expr_with_paren _ =
    let ast = parse_repl_string "1+(2+3)" in
    assert_equal ast (Add (IntLit 1, Add (IntLit 2, IntLit 3)))

let eval_expr_with_paren _ =
    let value = eval_string "1+(2+3)" in
    assert_equal value (IntVal 6)

let parse_let _ =
    let ast = parse_repl_string "let x = 1 in x" in
    assert_equal ast (Let ("x", IntLit 1, Var "x"))

let parse_op_let _ =
    let ast = parse_repl_string "1 + let x = 1 in x" in
    assert_equal ast (Add (IntLit 1, Let ("x", IntLit 1, Var "x")))

let parse_let_op _ =
    let ast = parse_repl_string "(let x = 1 in x) + 1" in
    assert_equal ast (Add (Let ("x", IntLit 1, Var "x"), IntLit 1))

let parse_let_let _ =
    let ast = parse_repl_string "let x = let y = 1 in y in let z = x in z" in
    let expected = Let ("x", Let ("y", IntLit 1, Var "y"), Let ("z", Var "x", Var "z")) in
    assert_equal ast expected

let parse_let_stmts _ =
    let ast = parse_string "let x = 1 let y = 1" in
    assert_equal ast [LetStmt("x", IntLit 1); LetStmt("y", IntLit 1)]

let eval_let _ =
    let ast = eval_string "let x = 1 in let y = 2 in let x = 3 in x + y" in
    assert_equal ast (IntVal 5)

let parse_emp_list1 _ =
    let ast = parse_repl_string "[ ]" in
    assert_equal ast Emp

let parse_emp_list2 _ =
    let ast = parse_repl_string "[]" in
    assert_equal ast Emp

let parse_list_single1 _ =
    let ast = parse_repl_string "[1]" in
    assert_equal ast (Cons (IntLit 1, Emp))

let parse_list_single2 _ =
    let ast = parse_repl_string "[1;]" in
    assert_equal ast (Cons (IntLit 1, Emp))

let parse_list1 _ =
    let ast = parse_repl_string "[1;2;3]" in
    assert_equal ast (Cons (IntLit 1, Cons (IntLit 2, Cons (IntLit 3, Emp))))

let parse_list2 _ =
    let ast = parse_repl_string "[1;2;3;]" in
    assert_equal ast (Cons (IntLit 1, Cons (IntLit 2, Cons (IntLit 3, Emp))))

let parse_tuple1 _ =
    let ast = parse_repl_string "1, 2" in
    assert_equal ast (Tuple [IntLit 1; IntLit 2])

let parse_tuple2 _ =
    let ast = parse_repl_string "1+2, 2+3" in
    assert_equal ast (Tuple [Add (IntLit 1, IntLit 2); Add(IntLit 2, IntLit 3)])

let parse_tuple3 _ =
    let ast = parse_repl_string "1, 2, 3, 4" in
    assert_equal ast (Tuple [IntLit 1; IntLit 2; IntLit 3; IntLit 4])

let parse_tuple_list1 _ =
    let ast = parse_repl_string "[1,2]" in
    assert_equal ast (Cons (Tuple [IntLit 1; IntLit 2], Emp))

let parse_tuple_list2 _ =
    let ast = parse_repl_string "[1,2;3,4]" in
    assert_equal ast (Cons (Tuple [IntLit 1; IntLit 2], Cons (Tuple [IntLit 3; IntLit 4], Emp)))

let eval_tuple _ =
    let value = eval_string "let x = 1 in x, 1+1, let y = 3 in y, 4" in
    let expected = TupleVal [IntVal 1; IntVal 2; TupleVal [IntVal 3; IntVal 4]] in
    assert_equal value expected

let parse_4arith _ =
    let ast = parse_repl_string "3*(200+300)/4-5" in
    let expected = Sub (
        Div (Mul (IntLit 3, Add (IntLit 200, IntLit 300)), IntLit 4),
        IntLit 5
    )
    in assert_equal ast expected

let parse_cmp_and _ =
    let ast = parse_repl_string "3>2 && not not (1 < 0)" in
    let expected = And (
        Gret(IntLit 3, IntLit 2),
        Not (Not (Less(IntLit 1, IntLit 0)))
    )
    in assert_equal ast expected

let parse_bool_op _ =
    let ast = parse_repl_string "true && false || 1 = 2 && false" in
    let expected = Or (
        And (BoolLit true, BoolLit false),
        And (Eq (IntLit 1, IntLit 2), BoolLit false)
    )
    in assert_equal ast expected

let eval_4arith _ =
    let ast = eval_string "3*(200+300)/4-5" in
    assert_equal ast (IntVal 370)

let eval_gret _ =
    let value = eval_string "3 > 2" in
    assert_equal value (BoolVal true)

let eval_less _ =
    let value = eval_string "3 < 2" in
    assert_equal value (BoolVal false)

let eval_and _ =
    let value = eval_string "true && false" in
    assert_equal value (BoolVal false)

let eval_or _ =
    let value = eval_string "true || false" in
    assert_equal value (BoolVal true)

let eval_not _ =
    let value = eval_string "not true" in
    assert_equal value (BoolVal false)

let eval_eq _ =
    let value = eval_string "1 = 1 && true = true" in
    assert_equal value (BoolVal true)

let parse_match1 _ =
    let ast = parse_repl_string "match x with y -> 0 | z -> match z with a -> a" in
    let expected = Match (Var "x", [
        (PVar "y", IntLit 0);
        (PVar "z", Match (Var "z", [PVar "a", Var "a"]));
    ])
    in assert_equal ast expected

let parse_match2 _ =
    let ast = parse_repl_string "match x with y -> let x = 1 in x | z -> 1" in
    let expected = Match (Var "x", [
        (PVar "y", Let ("x", IntLit 1, Var "x"));
        (PVar "z", IntLit 1);
    ])
    in assert_equal ast expected

let parse_builtin _ =
    let ast = parse_repl_string "builtin \"hd\"" in
    let expected = Builtin "hd" in
    assert_equal ast expected

let parse_debugprint _ =
    let ast = parse_repl_string "debugprint 1" in
    let expected = DebugPrint (IntLit 1) in
    assert_equal ast expected

let parse_app1 _ =
    let ast = parse_repl_string "a b c" in
    let expected = App (App (Var "a", Var "b"), Var "c") in
    assert_equal ast expected

let parse_app2 _ =
    let ast = parse_repl_string "1 + a b" in
    let expected = Add (IntLit 1, App (Var "a", Var "b")) in
    assert_equal ast expected

let parse_app3 _ =
    let ast = parse_repl_string "(a b) c" in
    let expected = App (App (Var "a", Var "b"), Var "c") in
    assert_equal ast expected

let parse_app_list _ =
    let ast = parse_repl_string "[a b]" in
    let expected = Cons (App (Var "a", Var "b"), Emp) in
    assert_equal ast expected

let parse_seq _ =
    let ast = parse_repl_string "a;b;c" in
    let expected = Seq (Var "a", Seq (Var "b", Var "c")) in
    assert_equal ast expected

let parse_let_seq _ =
    let ast = parse_repl_string "let x = 1 in 0;x" in
    let expected = Let ("x", IntLit 1, Seq (IntLit 0, Var "x")) in
    assert_equal ast expected

let parse_seq_match _ =
    let ast = parse_repl_string "match x with x -> 0;0 | y -> 1;1" in
    let expected = Match (Var "x", [
        (PVar "x", Seq(IntLit 0, IntLit 0));
        (PVar "y", Seq(IntLit 1, IntLit 1));
    ])in
    assert_equal ast expected

let eval_seq _ =
    let value = eval_string "1; 2; 3" in
    assert_equal value (IntVal 3)

let eval_let_seq _ =
    let value = eval_string "let x = 1 in 0; let y = x in y" in 
    assert_equal value (IntVal 1)

let parse_cons _ =
    let ast = parse_repl_string "1 :: 2 :: []" in
    let expected = Cons(IntLit 1, Cons(IntLit 2, Emp)) in
    assert_equal ast expected

let eval_list _ =
    let value = eval_string "(1 + 2) :: (3*7) :: [9]" in
    assert_equal value (ListVal [IntVal 3; IntVal 21; IntVal 9])

let parse_fun _ =
    let ast = parse_repl_string "fun x y z -> x + y + z" in
    let expected = Fun("x", Fun ("y", Fun ("z", Add(Add(Var "x", Var "y"), Var "z")))) in
    assert_equal ast expected

let eval_fun1 _ =
    let value = eval_string "(fun x -> x + 1) 1" in
    assert_equal value (IntVal 2)

let eval_fun2 _ =
    let value = eval_string "(fun x y -> x + y) 1 2" in
    assert_equal value (IntVal 3)

let suite =
    "Kadai6" >::: [
        "parse_str" >:: parse_str;
        "parse_add1" >:: parse_add1;
        "parse_add2" >:: parse_add2;
        "eval_add" >:: eval_add;
        "parse_mod" >:: parse_mod;
        "eval_mod" >:: eval_mod;
        "parse_expr_with_paren" >:: parse_expr_with_paren;
        "eval_expr_with_paren" >:: eval_expr_with_paren;
        "parse_let" >:: parse_let;
        "parse_op_let" >:: parse_op_let;
        "parse_let_let" >:: parse_let_let;
        "eval_let" >:: eval_let;
        "parse_emp_list1" >:: parse_emp_list1;
        "parse_emp_list2" >:: parse_emp_list2;
        "parse_list_single1" >:: parse_list_single1;
        "parse_list_single2" >:: parse_list_single2;
        "parse_list1" >:: parse_list1;
        "parse_list2" >:: parse_list2;
        "parse_tuple1" >:: parse_tuple1;
        "parse_tuple2" >:: parse_tuple2;
        "parse_tuple3" >:: parse_tuple3;
        "parse_tuple_list1" >:: parse_tuple_list1;
        "parse_tuple_list2" >:: parse_tuple_list2;
        "eval_tuple" >:: eval_tuple;
        "parse_cmp_and" >:: parse_cmp_and;
        "parse_bool_op" >:: parse_bool_op;
        "parse_4arith" >:: parse_4arith;
        "eval_4arith" >:: eval_4arith;
        "eval_gret" >:: eval_gret;
        "eval_less" >:: eval_less;
        "eval_and" >:: eval_and;
        "eval_or" >:: eval_or;
        "eval_not" >:: eval_not;
        "eval_eq" >:: eval_eq;
        "eval_let_seq" >:: eval_let_seq;
        "parse_match1" >:: parse_match1;
        "parse_match2" >:: parse_match2;
        "parse_builtin" >:: parse_builtin;
        "parse_debugprint" >:: parse_debugprint;
        "parse_app1" >:: parse_app1;
        "parse_app2" >:: parse_app2;
        "parse_app3" >:: parse_app3;
        "parse_app_list" >:: parse_app_list;
        "parse_seq" >:: parse_seq;
        "parse_let_seq" >:: parse_let_seq;
        "parse_seq_match" >:: parse_seq_match;
        "eval_seq" >:: eval_seq;
        "parse_cons" >:: parse_cons;
        "eval_list" >:: eval_list;
        "parse_fun" >:: parse_fun;
        "eval_fun1" >:: eval_fun1;
        "eval_fun2" >:: eval_fun2;
    ]
