let gcd n m =
    (* 計算の本体部分 *)
    let rec f n m = if n = 0 then m else f (m mod n) n in
    (* 予め絶対値を取ってから本実装に渡す *)
    f (min (abs n) (abs m)) (max (abs n) (abs m))

(* 負数の場合は0を返す *)
let rec fib = function
    | 1 -> 1
    | 2 -> 1
    | n when n > 0 -> fib (n - 1) + fib (n - 2)
    | _ -> 1

(* 第n-2項と第n-1項を引数として渡し続けることでメモ化 *)
let fib2 n =
    let rec f (acc1, acc2) m =
        if n <= m then acc2 else f (acc2, acc1 + acc2) (m + 1)
    in
    f (0, 1) 1

(* 一般項を用いて計算。多分これが一番速いです *)
let fib3 n =
    (* O(log n)で計算できるpow *)
    let rec pow e = function
        | 0 -> 1.
        | n when n mod 2 = 0 ->
            let y = pow e (n / 2) in
            y *. y
        | n -> e *. pow e (n - 1)
    in
    1. /. sqrt 5.
    *. (pow ((1. +. sqrt 5.) /. 2.) n -. pow ((1. -. sqrt 5.) /. 2.) n)
    |> int_of_float

let prime n =
    (* naive implementation *)
    (* 素数リストを持ち回す。一つずつ整数を増やしつつそれが今までの素数リストの要素で割り切れたら無視、
     * 割り切れなかったら新たに素数リストに加える。
     * 毎回素数リストの長さをチェックし、必要数に達していれば先頭(=最大)の素数を返す *)
    let rec f primes m =
        if n == List.length primes then List.hd primes
        else if List.for_all (fun prime -> m mod prime != 0) primes then
          f (m :: primes) (m + 1)
        else f primes (m + 1)
        (* 初期の素数には2を与え、3からチェックを始める *)
    in
    f [2] 3

(* KMPアルゴリズムを使うべきかと思ったが、KMPは手続き的にしか実装できないように思えたのでやめた*)
let substring s1 s2 =
    (* *.initを使って文字列を文字の羅列に変換する一般的なテク *)
    let explode s = List.init (String.length s) (String.get s) in
    let s1 = explode s1 in
    let s2 = explode s2 in
    (* s2が空なら無条件で一致 *)
    (* s1が空かつs2が空でなければ一致することはない *)
    (* それ以外では先頭の文字を順に短絡評価 *)
    let rec check = function
        | _, [] -> true
        | [], _ -> false
        | c1 :: s1, c2 :: s2 -> c1 = c2 && check (s1, s2)
    in
    let rec search i = function
        | [] ->
            (* どちらも空な場合は0 *)
            if List.length s2 = 0 then 0 else -1
        (* 一文字づつずらしてcheckをしていく *)
        | _ :: last as s1 -> if check (s1, s2) then i else search (i + 1) last
    in
    search 0 s1

let rec qsort = function
    (* 要素数1以下は並び替えの必要なし *)
    | [] -> []
    | [n] -> [n]
    (* 先頭をピボットとしてList.filterを用いてピボット以下とピボットより大きいものを分ける
     * その2つの部分を分割統治で再帰的に処理する。
     * ピボットは再帰でソートした2つのリストの間に挿入する
     * これにより毎回最低でも1つはピボットとしてソート対象から消えるので必ず収束する *)
    | pivot :: remain ->
        let l1 = List.filter (fun n -> pivot < n) remain in
        let l2 = List.filter (fun n -> pivot >= n) remain in
        List.append (qsort l2) (pivot :: qsort l1)
