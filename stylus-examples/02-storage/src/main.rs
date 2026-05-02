// A simple program that bumps the 0 storage slot on its last byte,
// before wrapping around.

#![no_std]
#![no_main]

#[panic_handler]
fn panic_handler(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

#[link(wasm_import_module = "vm_hooks")]
unsafe extern "C" {
    fn pay_for_memory_grow(pages: usize);
    fn storage_flush_cache(clear: bool);
    fn storage_load_bytes32(key: *const u8, out: *mut u8);
    fn storage_cache_bytes32(key: *const u8, from: *const u8);
}

#[unsafe(no_mangle)]
fn user_entrypoint(_: usize) -> usize {
    let key = [0u8; 32];
    let mut val = [0u8; 32];
    unsafe {
        storage_load_bytes32(key.as_ptr(), val.as_mut_ptr());
    }
    val[31] += 1;
    unsafe {
        storage_cache_bytes32(key.as_ptr(), val.as_ptr());
        storage_flush_cache(true);
    }
    0
}

#[unsafe(no_mangle)]
pub unsafe fn mark_used() {
    unsafe { pay_for_memory_grow(0) }
    panic!();
}