ifndef K_VERSION
$(error K_VERSION not set. Please use the Build script, instead of running make directly)
endif

.PHONY: all clean build tangle defn proofs evm-prime split-tests test

all: build split-tests

clean:
	rm -r .build
	find tests/proofs/ -name '*.k' -delete

build: tangle .build/${K_VERSION}/ethereum-kompiled/extras/timestamp

# Tangle from *.md files
# ----------------------

tangle: defn proofs evm-prime

### Definition

defn_dir=.build/${K_VERSION}
defn_files=${defn_dir}/ethereum.k ${defn_dir}/data.k ${defn_dir}/evm.k ${defn_dir}/analysis.k ${defn_dir}/krypto.k ${defn_dir}/verification.k ${defn_dir}/evm-prime.k

defn: $(defn_files)

.build/${K_VERSION}/%.k: %.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code ${K_VERSION} $< > $@

### Proofs

proof_dir=tests/proofs
proof_files=${proof_dir}/sum-to-n-spec.k \
			${proof_dir}/hkg/allowance-spec.k \
			${proof_dir}/hkg/approve-spec.k \
			${proof_dir}/hkg/balanceOf-spec.k \
			${proof_dir}/hkg/transfer-else-spec.k ${proof_dir}/hkg/transfer-then-spec.k \
			${proof_dir}/hkg/transferFrom-else-spec.k ${proof_dir}/hkg/transferFrom-then-spec.k

proofs: $(proof_files)

tests/proofs/sum-to-n-spec.k: proofs/sum-to-n.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code sum-to-n $< > $@

tests/proofs/hkg/%-spec.k: proofs/hkg.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code $* $< > $@

### EVM-PRIME

tests/evm-prime/example.evm: evm-prime.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code example evm-prime.md > $@

evm-prime: tests/evm-prime/example.evm

# Tests
# -----

split-tests: tests/VMTests/vmArithmeticTest/make.timestamp \
			 tests/VMTests/vmBitwiseLogicOperationTest/make.timestamp \
			 tests/VMTests/vmBlockInfoTest/make.timestamp \
			 tests/VMTests/vmEnvironmentalInfoTest/make.timestamp \
			 tests/VMTests/vmIOandFlowOperationsTest/make.timestamp \
			 tests/VMTests/vmLogTest/make.timestamp \
			 tests/VMTests/vmPerformanceTest/make.timestamp \
			 tests/VMTests/vmPushDupSwapTest/make.timestamp \
			 tests/VMTests/vmSha3Test/make.timestamp \
			 tests/VMTests/vmSystemOperationsTest/make.timestamp \
			 tests/VMTests/vmtests/make.timestamp \
			 tests/VMTests/vmInputLimits/make.timestamp \
			 tests/VMTests/vmInputLimitsLight/make.timestamp

passing_test_file=tests/passing.expected
all_tests=$(wildcard tests/VMTests/*/*.json)
skipped_tests=$(wildcard tests/VMTests/vmPerformanceTest/*.json) tests/VMTests/vmIOandFlowOperationsTest/loop_stacklimit_1021.json
passing_tests=$(filter-out ${skipped_tests}, ${all_tests})
passing_targets=${passing_tests:=.test}

test: $(passing_targets)

tests/%.test: tests/% build
	./evm $<

tests/%/make.timestamp: tests/ethereum-tests/%.json
	@echo "==   split: $@"
	mkdir -p $(dir $@)
	tests/split-test.py $< $(dir $@)
	touch $@

tests/ethereum-tests/%.json:
	@echo "==  git submodule: cloning upstreams test repository"
	git submodule update --init

<<<<<<< HEAD
# Building UIUC K
=======
tests/evm-prime/demo.evm: evm-prime.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code demo evm-prime.md > $@

# UIUC K Specific
>>>>>>> wip: evm-prime.md added
# ---------------

.build/uiuck/ethereum-kompiled/extras/timestamp: $(defn_files)
	@echo "== kompile: $@"
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/uiuck

# Building RV K
# -------------

.build/rvk/ethereum-kompiled/extras/timestamp: .build/rvk/ethereum-kompiled/interpreter
.build/rvk/ethereum-kompiled/interpreter: $(defn_files) KRYPTO.ml
	@echo "== kompile: $@"
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/rvk \
					--hook-namespaces KRYPTO --gen-ml-only -O3 --non-strict
	ocamlfind opt -c .build/rvk/ethereum-kompiled/constants.ml -package gmp -package zarith
	ocamlfind opt -c -I .build/rvk/ethereum-kompiled KRYPTO.ml -package cryptokit
	ocamlfind opt -a -o semantics.cmxa KRYPTO.cmx
	ocamlfind remove ethereum-semantics-plugin
	ocamlfind install ethereum-semantics-plugin META semantics.cmxa semantics.a KRYPTO.cmi KRYPTO.cmx
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/rvk \
					--hook-namespaces KRYPTO --packages ethereum-semantics-plugin -O3 --non-strict
	cd .build/rvk/ethereum-kompiled && ocamlfind opt -o interpreter constants.cmx prelude.cmx plugin.cmx parser.cmx lexer.cmx run.cmx interpreter.ml -package gmp -package dynlink -package zarith -package str -package uuidm -package unix -linkpkg -inline 20 -nodynlink -O3
