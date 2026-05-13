#[cfg(feature = "export-abi")]
fn main() {
    cluj_email::print_from_args();
}

#[cfg(not(feature = "export-abi"))]
fn main() {}
