#!/bin/sh

find bin -type f -name '*.ml' | xargs ocamlformat --check $f && \
find lib -type f -name '*.ml' | xargs ocamlformat --check $f && \
find test -type f -name '*.ml' | xargs ocamlformat --check $f
