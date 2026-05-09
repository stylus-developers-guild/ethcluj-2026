#[cfg(feature = "export-abi")]
fn main() {
    cluj_lending::print_abi("MIT", "pragma solidity ^0.8.23;");
}

#[cfg(not(feature = "export-abi"))]
fn main() {}
