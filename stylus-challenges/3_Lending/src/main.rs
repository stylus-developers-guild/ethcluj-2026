#[cfg(feature = "export-abi")]
fn main() {
    cluj_lending::print_from_args();
}

#[cfg(not(feature = "export-abi"))]
fn main() {}
