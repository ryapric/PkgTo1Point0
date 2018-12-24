# Basic julia call with colors
juliab = julia --color=yes

# Project-based julia calls with colors
juliapg = julia --color=yes --project="$$PKGNAME"
juliap = julia --color=yes --project

# Bare package name provided, in case it includes path info
PKGNAMEBARE := $$(echo "$${PKGNAME}" | sed -r 's/^.*\/([A-Za-z0-9_\-]+)$$/\1/')

all: precompile build test

FORCE:

# precompile() is not an exported function from Pkg; just a command in the REPL
# So, it can be accessed via Pkg.REPLMode.pkgstr()
precompile: FORCE
	@$(juliap) -e "using Pkg; Pkg.REPLMode.pkgstr(\"precompile\")"

build: FORCE
	@$(juliap) -e "using Pkg; Pkg.build()"

test: FORCE
	@$(juliap) -e "using Pkg; Pkg.test()"

doc: FORCE
	@# Note that make.jl needs to be run from the docs directory
	@cd docs && $(juliap) make.jl && cd $$OLDPWD
