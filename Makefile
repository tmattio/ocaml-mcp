VENDORED_DIR=vendor
VENDORED_TARGS=$(wildcard $(VENDORED_DIR)/*/)

.PHONY: all build clean test init

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

# Help target
help:
	@echo "Available targets:"
	@echo "  init         - Initialize/update submodules and dependencies"
	@echo "  build        - Build the project using dune"
	@echo "  clean        - Clean build artifacts"
	@echo "  test         - Run tests with dune runtest"
	@echo "  help         - Show this help message"
