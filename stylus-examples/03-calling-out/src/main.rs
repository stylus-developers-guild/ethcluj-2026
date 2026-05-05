// A simple program that interacts with the Arbitrum precompiles to get
// the current block.

#![no_std]
#![no_main]

#[panic_handler]
fn panic_handler(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

#[link(wasm_import_module = "vm_hooks")]
unsafe extern "C" {
    fn pay_for_memory_grow(pages: usize);
    fn write_result(d: *const u8, l: usize);
    fn static_call_contract(
        contract: *const u8,
        calldata: *const u8,
        calldata_len: usize,
        gas: u64,
        return_data_len: *mut usize,
    ) -> u8;
    fn read_return_data(dest: *mut u8, offset: usize, size: usize) -> usize;
}

#[unsafe(no_mangle)]
fn user_entrypoint(_: usize) -> usize {
    let addr: [u8; 20] =
        const_hex::decode_to_array("0000000000000000000000000000000000000064").unwrap();
    let mut b = [0u8; 32];
    let cd: [u8; 4] = const_hex::decode_to_array("a3b1b31d").unwrap();
    let mut return_len = 0usize;
    unsafe {
        static_call_contract(
            addr.as_ptr(),
            cd.as_ptr(),
            4,
            u64::MAX,
            &mut return_len as *mut usize,
        );
        read_return_data(b.as_mut_ptr(), 0, 32);
        write_result(b.as_ptr(), 32);
    }
    0
}

#[unsafe(no_mangle)]
pub unsafe fn mark_used() {
    unsafe { pay_for_memory_grow(0) }
    panic!();
}
