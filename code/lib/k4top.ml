let parse f lexbuf =
    let open K4lex in
    let lexer () =
        let ante_position = lexbuf.pos in
        let token = lex lexbuf in
        let post_position = lexbuf.pos
        in (token, ante_position, post_position) in
    let parser =
        MenhirLib.Convert.Simplified.traditional2revised f
    in
    parser lexer

let parse_string s =
    let buf = K4lex.create_lexbuf ~file:"no file"
        @@ Sedlexing.Utf8.from_string s in
    parse K4parser.main buf

let eval_string s =
    let ast = parse_string s in
    K4ast.eval (K4ast.emptyenv ()) ast