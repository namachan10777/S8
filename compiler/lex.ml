type pos_t = string * int * int * int

let count_newline s =
    let rec cnt acc i_begin i_end =
        if i_begin == i_end
        then acc
        else if s.[i_begin] = '\n'
        then cnt (acc+1) (i_begin+1) i_end
        else cnt acc (i_begin+1) i_end
    in cnt 0

let match_space_char s i =
    if i >= String.length s
    then None
    else if s.[i] = ' ' || s.[i] = '\t' || s.[i] = '\n' || s.[i] = '\r'
    then Some (i+1)
    else None

let match_alph_char s i =
    if i >= String.length s
    then None
    else
        let code = Char.code s.[i] in
        if code >= 0x41 && code <= 0x5a || code >= 61 && code <= 0x7a
        then Some(i+1)
        else None

let match_num_char s i =
    if i >= String.length s
    then None
    else
        let code = Char.code s.[i] in
        if code >= 0x30 && code <= 0x39
        then Some(i+1)
        else None

let match_char c s i =
    if i >= String.length s
    then None
    else
        if c = s.[i]
        then Some(i+1)
        else None

let match_str pat s i =
    if (i + String.length pat) > String.length s
    then None
    else
        if  pat  = String.sub s i (String.length pat)
        then Some(i+String.length pat)
        else None

let opt pat s =
    let rec f acc i = match (acc, pat s i) with
        | (_, Some res) -> f (Some res) (i+1)
        | (before, None) -> before
    in f None 

let match_space = opt match_space_char
let match_alph = opt match_alph_char
let match_num = opt match_num_char

let () =
    Test.assert_eq "count_newline 0 11" (count_newline "foo\nbar\nhoge" 0 11) 2;
    Test.assert_eq "count_newline 0 3" (count_newline "foo\nbar\nhoge" 0 3) 0;
    Test.assert_eq "count_newline 0 4" (count_newline "foo\nbar\nhoge" 0 4) 1;
    Test.assert_eq "count_newline 3 8" (count_newline "foo\nbar\nhoge" 3 8) 2;
    Test.assert_eq "match_space_char \" abc\" 0" (match_space_char " abc" 0) (Some 1);
    Test.assert_eq "match_space_char \" abc\" 1" (match_space_char " abc" 1) None;
    Test.assert_eq "match_space_char \"abc\" 0" (match_space_char "abc" 0) None;
    Test.assert_eq "match_space \" \\n\\r\\t\"" (match_space " \n\r\t" 0) (Some 4);
    Test.assert_eq "match_space \" \\n\\r\\t\" from 2" (match_space " \n\r\t" 2) (Some 4);
    Test.assert_eq "match_space \" \\n\\r\\thoge\" from 2 ends normal char" (match_space " \n\r\thoge" 2) (Some 4);
    Test.assert_eq "match_space \" \\n\\r\\thoge\" ends normal char" (match_space " \n\r\thoge" 0) (Some 4);
    Test.assert_eq "match_space \"hoo\"" (match_space "hoo" 0) None;
    Test.assert_eq "match_alph \"abc \"" (match_alph "abc " 0) (Some 3);
    Test.assert_eq "match_alph \" abc\"" (match_alph " abc" 0) None;
    Test.assert_eq "match_alph \"123a\"" (match_num "123a" 0) (Some 3);
    Test.assert_eq "match_alph \"a123\"" (match_num "a123" 0) None;
    Test.assert_eq "match_char '.' \".a\"" (match_char '.' ".a" 0) (Some 1);
    Test.assert_eq "match_char '.' \"a.\"" (match_char '.' "a." 0) None;
    Test.assert_eq "match_str \"hoge\" \"hoge\"" (match_str "hoge" "hoge" 0) (Some 4);
    Test.assert_eq "match_str \"hoge\" \"hog\"" (match_str "hoge" "hog" 0) None;
    Test.assert_eq "match_str \"hoge\" \"hogu\"" (match_str "hoge" "hogu" 0) None;
    Test.assert_eq "match_str \"hoge\" \" hoge\"" (match_str "hoge" " hoge" 1) (Some 5);
