use stylus_sdk::alloy_primitives::{address, Address, U256};

/// Address of ARB on Arbitrum Mainnet.
pub const ARB_ADDR: Address = address!("912CE59144191C1204E64559FE8253a0e49E6548");

/// Scaling factor to use for any mul_div operation in lieu of decimal math.
//1e18
pub const SCALING_FACTOR: U256 = U256::from_limbs([1000000000000000000, 0, 0, 0]);

/// Scaled interest rate per second.
//0.005 / (365 * 24 * 60 * 60) = 158548960
pub const INTEREST_PER_SEC_RATE: U256 = U256::from_limbs([158548960, 0, 0, 0]);

/// Scaled collateral requirement (1.10).
pub const COLLATERAL_REQ: U256 = U256::from_limbs([1100000000000000000, 0, 0, 0]);

/// Scaled security deposit (0.005).
pub const SECURITY_DEPOSIT: U256 = U256::from_limbs([5000000000000000, 0, 0, 0]);
