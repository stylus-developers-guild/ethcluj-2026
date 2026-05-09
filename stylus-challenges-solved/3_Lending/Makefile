
RELEASE_OUT := target/wasm32-unknown-unknown/release/cluj_lending.wasm

build: contract-lending.wasm

contract-lending.wasm: $(shell find src -name '*.rs')
	@rm -f contract-lending.wasm
	@cargo build --release --target wasm32-unknown-unknown
	@cp ${RELEASE_OUT} contract-lending.wasm

export-abi:
	@cargo run --features export-abi
