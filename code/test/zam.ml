open OUnit2
open S8.Zam

let emp_zam = {
    code = [];
    rstack = [];
    astack = [];
    env = [];
}

let test_finish _ =
    let zam = { emp_zam with astack = [Int 42] } in
    assert_equal (exec zam) (Int 42)

let test_finish2 _ =
    let zam = { emp_zam with astack = [Int 42]; env = [Int 42] } in
    assert_raises (Failure "invalid state") (fun _ -> exec zam)

let test_ldi _ =
    let zam = { emp_zam with code = [Ldi 42] } in
    assert_equal (exec zam) (Int 42)

let test_ldb _ =
    let zam = { emp_zam with code = [Ldb true] } in
    assert_equal (exec zam) (Bool true)

let test_lds _ =
    let zam = { emp_zam with code = [Lds "hoge"] } in
    assert_equal (exec zam) (Str "hoge")

let test_access _ =
    let zam = { emp_zam with code = [Access 1; EndLet; EndLet]; env = [Int 42; Str "hoge"] } in
    assert_equal (exec zam) (Str "hoge")

let test_let _ =
    let zam = { emp_zam with code = [Ldi 42; Let; Access 0; EndLet]; } in
    assert_equal (exec zam) (Int 42)

(* (fun x -> x) 42 *)
let test_clos_and_app _ =
    let zam = { emp_zam with
        code = [
            PushMark;
            Ldi 42;
            Closure [Access 0; Return];
            App;
        ]
    } in
    assert_equal (exec zam) (Int 42)

let test_test _ =
    let zam = { emp_zam with
        code = [
            Ldb true;
            Test (
                [Ldi 42],
                [Ldi 2]
            )
        ]
    } in
    assert_equal (exec zam) (Int 42)

let suite =
    "Zam" >::: [
        "finish" >:: test_finish;
        "finish2" >:: test_finish2;
        "test_ldi" >:: test_ldi;
        "test_ldb" >:: test_ldb;
        "test_lds" >:: test_lds;
        "test_access" >:: test_access;
        "test_let" >:: test_let;
        "test_test" >:: test_test;
        "test_app" >:: test_clos_and_app;
    ]
