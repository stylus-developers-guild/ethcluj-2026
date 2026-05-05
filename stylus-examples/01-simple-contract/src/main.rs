// A simple program that returns whatever it's given.

#![no_std]
#![no_main]

// When something terrible happens, the program will jump to this
// function to handle a problem and blow up if it can.
#[panic_handler]
fn panic_handler(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

// For us to interact with the broader blockchain, in the Rust
// programming language, we must use these functions:
#[link(wasm_import_module = "vm_hooks")]
unsafe extern "C" {
    fn pay_for_memory_grow(pages: usize);
    fn read_args(out: *mut u8);
    fn write_result(d: *const u8, l: usize);
}

// And we must define this function ourselves if we can. This function is
// replaced during the later conversion of this program to the
// sequencer's native code.
#[unsafe(no_mangle)]
pub unsafe fn mark_used() {
    unsafe { pay_for_memory_grow(0) }
    panic!();
}

// The actual entrypoint for our contract. WASM code starts running by
// the host running the WASM code addressing a specific function.
#[unsafe(no_mangle)]
fn user_entrypoint(len: usize) -> usize {
    let mut x = [0u8; 1024];
    assert!(x.len() >= len);
    unsafe {
        read_args(x.as_mut_ptr());
        write_result(x.as_ptr(), len);
    }
    0
}
