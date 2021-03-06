OCAMLOPT=ocamlfind ocamlopt -g -package ppx_deriving.show

.PHONY: all
all: test 1st

.PHONY: clean
clean:
	rm -f *.cmo
	rm -f *.cmx
	rm -f *.cmi
	rm -f *.cmt
	rm -f *.o
	rm -f *_test
	rm -f compiler
	rm -f *.pp.ml

.PHONY: test
test: lex_test id_test parser_test typing_test alpha_test closure_test types_test
	./lex_test
	./id_test
	./parser_test
	./alpha_test
	./typing_test
	./closure_test
	./types_test

lex.cmx: lex.ml
	$(OCAMLOPT) $< -c
lex_test.cmx: lex_test.ml lex.cmx
	$(OCAMLOPT) $< -c
lex_test: lex.cmx lex_test.cmx
	$(OCAMLOPT) $^ -o $@

id.cmx: id.ml
	$(OCAMLOPT) $< -c
id_test.cmx: id_test.ml id.cmx
	$(OCAMLOPT) $< -c
id_test:  id.cmx id_test.cmx
	$(OCAMLOPT) $^ -o $@

util.cmx: util.ml
	$(OCAMLOPT) $< -c
tbl.cmx: tbl.ml
	$(OCAMLOPT) $< -c

parser.cmx: parser.ml id.cmx lex.cmx
	$(OCAMLOPT) $< -c
parser_test.cmx: parser_test.ml util.cmx parser.cmx
	$(OCAMLOPT) $< -c
parser_test: lex.cmx id.cmx util.cmx parser.cmx parser_test.cmx
	$(OCAMLOPT) $^ -o $@

types.cmx: types.ml id.cmx
	$(OCAMLOPT) $< -c
types_test.cmx: types_test.ml id.cmx types.cmx
	$(OCAMLOPT) $< -c
types_test: id.cmx types.cmx types_test.cmx
	$(OCAMLOPT) $^ -o $@

pervasives.cmx: pervasives.ml id.cmx types.cmx
	$(OCAMLOPT) $< -c

ast.cmx: ast.ml id.cmx parser.cmx types.cmx pervasives.cmx
	$(OCAMLOPT) $< -c

alpha.cmx: alpha.ml tbl.cmx ast.cmx id.cmx parser.cmx types.cmx pervasives.cmx
	$(OCAMLOPT) $< -c
alpha_test.cmx: alpha_test.ml alpha.cmx 
	$(OCAMLOPT) $< -c
alpha_test: lex.cmx id.cmx parser.cmx types.cmx pervasives.cmx tbl.cmx util.cmx ast.cmx alpha.cmx alpha_test.cmx
	$(OCAMLOPT) $^ -o $@

typing.cmx: typing.ml ast.cmx id.cmx parser.cmx types.cmx pervasives.cmx util.cmx
	$(OCAMLOPT) $< -c
typing_test.cmx: typing_test.ml typing.cmx 
	$(OCAMLOPT) $< -c
typing_test: id.cmx util.cmx tbl.cmx types.cmx pervasives.cmx lex.cmx parser.cmx ast.cmx alpha.cmx util.cmx tbl.cmx typing.cmx typing_test.cmx
	$(OCAMLOPT) $^ -o $@

closure.cmx: closure.ml typing.cmx ast.cmx id.cmx parser.cmx types.cmx pervasives.cmx util.cmx
	$(OCAMLOPT) $< -c
closure_test.cmx: closure_test.ml closure.cmx
	$(OCAMLOPT) $< -c
closure_test: id.cmx util.cmx tbl.cmx types.cmx pervasives.cmx lex.cmx parser.cmx ast.cmx alpha.cmx util.cmx tbl.cmx typing.cmx closure.cmx closure_test.cmx
	$(OCAMLOPT) $^ -o $@

main.cmx: main.ml typing.cmx alpha.cmx id.cmx parser.cmx types.cmx pervasives.cmx util.cmx
	$(OCAMLOPT) $< -c
1st: id.cmx lex.cmx util.cmx parser.cmx tbl.cmx types.cmx pervasives.cmx ast.cmx alpha.cmx typing.cmx main.cmx
	$(OCAMLOPT) $^ -o $@
