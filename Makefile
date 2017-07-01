.PHONY: bench benchmark build clean dump-th ghci haddock haddock-server hlint install test upload watch watch-test
all: build

# Run the benchmark.
bench: benchmark
benchmark:
	stack bench

# Build both hrep and highlight.
build: 
	stack build

# Clean up the built packages.
clean:
	stack clean

# Dump template haskell splices.
dump-th:
	-stack build --ghc-options="-ddump-splices"
	@echo
	@echo "Splice files:"
	@echo
	@find "$$(stack path --dist-dir)" -name "*.dump-splices" | sort

# Generate the documentation.
haddock:
	stack build --haddock

# Install highlight and hrep to ~/.local/bin/.
install:
	stack install

# Build while watching for changes.  Rebuild when change is detected.
watch:
	stack build --file-watch --fast .

# Run tests while watching for changes, rebuild and rerun tests when change is
# detected.
watch-test:
	stack test --file-watch --fast .

# Run ghci (REPL).
ghci:
	stack ghci

# Run the tests.
test:
	stack test

# Run hlint.
hlint:
	hlint src/

# This runs a small python websever on port 8001 serving up haddocks for
# packages you have installed.
#
# In order to run this, you need to have run `make build-haddock`.
haddock-server:
	cd "$$(stack path --local-doc-root)" && python -m http.server 8001

# Upload this package to hackage.
upload:
	stack upload .
