OCAMLOPT=ocamlfind ocamlopt -package ppx_deriving.show

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
test: lex_test id_test parser_test
	./lex_test
	./id_test
	./parser_test

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

parser.cmx: parser.ml id.ml lex.ml
	$(OCAMLOPT) $< -c
parser_test.cmx: parser_test.ml util.cmx parser.cmx id.cmx lex.cmx
	$(OCAMLOPT) $< -c
parser_test: lex.cmx id.cmx util.cmx parser.cmx parser_test.cmx
	$(OCAMLOPT) $^ -o $@
