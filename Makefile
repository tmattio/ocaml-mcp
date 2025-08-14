VENDORED_DIR=vendor
VENDORED_TARGS=$(wildcard $(VENDORED_DIR)/*/)

.PHONY: all init build clean test install

all: init build test

init: 
	git submodule update --init --recursive
	opam install -y --deps-only --with-test $(VENDORED_TARGS) .

build: 
	dune build

clean:
	dune clean

test: 
	dune runtest

install: init
	opam install $(VENDORED_TARGS) .
