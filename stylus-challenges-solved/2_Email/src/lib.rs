// In this example, senders of emails must pay the token that recipients
// have indicated that they receive. The recipients must indicate that
// they've received the emails from before until a buffer amount, at
// which point users can not send emails to the recipient. If the
// recipient does not claim their email inbox after a window has passed,
// the original senders can claim a refund, and the recipient will remain
// full. NOT FOR PRODUCTION. Does not check erc20 return values.

#![no_std]

extern crate alloc;

use stylus_sdk::{
    alloy_primitives::{Address, Bytes, U256, U32},
    alloy_sol_types::sol,
    prelude::*,
    storage::*,
};

use alloc::{vec, vec::Vec};

/// The word for the email storage is the sender (aka, the recipient) and the token id.
pub type StorageEmailWord = StorageU256;

#[repr(u8)]
#[derive(Clone, Debug, PartialEq)]
pub enum EmailStatus {
    RECEIVED,
    REFUNDED,
}

/// Email derived from StorageEmailWord.
#[derive(Debug, Clone)]
pub struct WordEmail {
    /// The recipient entitled to a refund if the email recipient does
    /// not process this email after the date:
    pub refund_recipient: Address,
    /// The token id they paid:
    pub token_id: u32,
    // The timestamp after epoch that we need to lift and check against
    // to see if they're entitled to a refund:
    pub ts_after_epoch: u32,
    // The status of the email, whether it was claimed or refunded.
    pub status: EmailStatus,
}

/// Maximum unread emails.
pub const MAX_UNREAD_EMAILS: u32 = 100;

/// The unread window that any senders become eligible for a refund if
/// the user does not read within that window for.
pub const UNREAD_WINDOW: u64 = 24 * 60 * 60 * 7;

#[entrypoint]
#[storage]
pub struct Storage {
    /// The timestamp epoch to add to any timestamp calculation.
    pub ts_epoch: StorageU64,

    /// Tokens that recipients are willing to receive, including their asks.
    pub token_asks: StorageMap<Address, StorageMap<U32, StorageU256>>,

    /// Token address lookup map to get the currently active token id based
    /// on the token given.
    pub enabled_tokens: StorageMap<Address, StorageMap<Address, StorageU32>>,

    /// The ids to token addresses that we use for a lookup during the claim.
    pub ids_to_tokens: StorageMap<Address, StorageMap<U32, StorageAddress>>,

    /// The place that the reading user is up to with their history.
    pub cursor: StorageMap<Address, StorageU32>,

    /// Emails received by the address given. In the word format.
    pub received_emails: StorageMap<Address, StorageVec<StorageEmailWord>>,
}

sol! {
    event EmailAdded(
        address indexed recipient,
        address indexed sender,
        bytes content
    );

    error ErrorContractNotConfigured();
    error ErrorContractTooOld();
    error ErrorTokenDisabled();
    error ErrorNotEnoughToken();
    error ErrorNoRecipient();
    error ErrorEmailTooBackedUp();
    error ErrorTooManyEmails();
    error ErrorTransfer(bytes);
    error ErrorPastDeadline();
    error ErrorTransferFrom(bytes);
}

sol_interface! {
    interface IERC20 {
        function transfer(address recipient, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
    }
}

#[derive(SolidityError)]
pub enum Error {
    ContractNotConfigured(ErrorContractNotConfigured),
    ContractTooOld(ErrorContractTooOld),
    TokenDisabled(ErrorTokenDisabled),
    NotEnoughToken(ErrorNotEnoughToken),
    NoRecipient(ErrorNoRecipient),
    TooManyEmails(ErrorTooManyEmails),
    EmailTooBackedUp(ErrorEmailTooBackedUp),
    Transfer(ErrorTransfer),
    PastDeadline(ErrorPastDeadline),
    TransferFrom(ErrorTransferFrom),
}

#[public]
impl Storage {
    /// Estimate the amount needed for a email to be sent to a recipient.
    pub fn estimate_amt_needed(&self, recipient: Address, token: Address) -> Result<U256, Error> {
        let token_id = self.enabled_tokens.getter(recipient).get(token);
        if token_id.is_zero() {
            return Err(Error::TokenDisabled(ErrorTokenDisabled {}));
        }
        Ok(self.token_asks.getter(recipient).get(token_id))
    }

    pub fn send_email(
        &mut self,
        recipient: Address,
        refund_recipient: Address,
        token: Address,
        max_amt: U256,
        content: Bytes,
    ) -> Result<U256, Error> {
        let current_ts = self.vm().block_timestamp();
        let ts_epoch = self.ts_epoch.get().into_limbs()[0];
        if ts_epoch == 0 {
            // The contract was not created after it was deployed! Don't allow use.
            return Err(Error::ContractNotConfigured(ErrorContractNotConfigured {}));
        }
        // First, check that the token given is enabled.
        let token_id = self.enabled_tokens.getter(recipient).get(token);
        if token_id.is_zero() {
            // The first value in this vector is always unset so we can make
            // use of this check.
            return Err(Error::TokenDisabled(ErrorTokenDisabled {}));
        }
        // The minimum token amount is the amount we'll actually take from
        // the user in the token they provided.
        let min_amt = self.token_asks.getter(recipient).get(token_id);
        // If the token amount is more than we can provide, then we break:
        if min_amt > max_amt {
            return Err(Error::NotEnoughToken(ErrorNotEnoughToken {}));
        }
        // Now, we need to check if the recipient is backed up too badly
        // right now to receive tokens. Ruint stores these numbers as little endian,
        // so this conversion is safe to make:
        let cursor = self.cursor.get(recipient).into_limbs()[0] as u32;
        // First, let's check if they have any unread emails. The
        // Stylus machine is natively u32, so we can safely cast
        // to u32. Let's ensure that they haven't exceeded the
        // limit:
        let received_count = self.received_emails.get(recipient).len() as u32;
        if received_count == u32::MAX {
            // Wow, that's a lot of emails!
            return Err(Error::TooManyEmails(ErrorTooManyEmails {}));
        }
        // It's safe to perform a wrapping subtraction here since the cursor
        // will never exceed the received count:
        let unread_emails = received_count - cursor;
        if unread_emails > MAX_UNREAD_EMAILS {
            // The user has more than the limit of emails they can have
            // before having trouble receiving them.
            return Err(Error::EmailTooBackedUp(ErrorEmailTooBackedUp {}));
        }
        // Check whether the next unread email has been waiting for too long:
        if unread_emails > 0 {
            let next_cursor = cursor
                .checked_add(1)
                .ok_or(Error::TooManyEmails(ErrorTooManyEmails {}))?;
            let WordEmail { ts_after_epoch, .. } = self
                .received_emails
                .setter(recipient)
                .get(next_cursor)
                .unwrap()
                .into();
            let ts_deadline = current_ts + ts_after_epoch as u64;
            // Add the timestamp from epoch to the latest unread email's time:
            let is_past_deadline = ts_deadline > current_ts + UNREAD_WINDOW;
            if is_past_deadline {
                return Err(Error::PastDeadline(ErrorPastDeadline {}));
            }
        }
        // Great! The recipient has been correctly receiving emails. Let's add
        // ours to the mix. We'll emit an event that says the user received their
        // email for off-chain consultation. We'll also add the user to the mix
        // for refunds.
        self.vm().log(EmailAdded {
            recipient,
            sender: refund_recipient,
            content,
        });
        // One final sanity check that our contract isn't too old:
        let ts_after_epoch = current_ts - ts_epoch;
        if ts_after_epoch > u32::MAX as u64 {
            // The contract is too old! We need to prevent people from using it.
            return Err(Error::ContractTooOld(ErrorContractTooOld {}));
        }
        // Finally, add the email to the mix for the recipient:
        let ts_after_epoch = ts_after_epoch as u32;
        let token_id = token_id.as_limbs()[0] as u32;
        let email = WordEmail {
            refund_recipient,
            token_id,
            ts_after_epoch,
            status: EmailStatus::RECEIVED,
        };
        self.received_emails.setter(recipient).push(email.into());
        // And take the amount from the user! This is not reentrant
        // thanks to security guarantees from Stylus.
        let config = Call::new_mutating(self);
        let sender = self.vm().msg_sender();
        let contract = self.vm().contract_address();
        IERC20::new(token)
            .transfer_from(self.vm(), config, sender, contract, min_amt)
            .map_err(|b| {
                let b: Vec<u8> = b.into();
                Error::TransferFrom(ErrorTransferFrom(b.into()))
            })?;
        Ok(min_amt)
    }

    /// Read email sent to this sender, returning the tokens that were
    /// received, and the amount of emails that were "read".
    pub fn read_email(&mut self, recipient: Address) -> Result<(Vec<Address>, Vec<U256>), Error> {
        let sender = self.vm().msg_sender();
        let cursor = self.cursor.get(sender).into_limbs()[0] as usize;
        let until = self.received_emails.getter(recipient).len();
        let remaining = cursor - until;
        if remaining == 0 {
            return Ok((Vec::new(), Vec::new()));
        }
        let mut token_addrs = Vec::with_capacity(remaining);
        let mut token_amts = Vec::with_capacity(remaining);
        for i in cursor..until {
            let WordEmail {
                token_id, status, ..
            } = self
                .received_emails
                .getter(recipient)
                .get(i)
                .unwrap()
                .into();
            if status != EmailStatus::RECEIVED {
                continue;
            }
            let token_id = U32::from(token_id);
            let token_addr = self.ids_to_tokens.getter(sender).get(token_id);
            let token = IERC20::new(token_addr);
            let amt = self.token_asks.getter(sender).get(token_id);
            let config = Call::new_mutating(self);
            token
                .transfer(self.vm(), config, recipient, amt)
                .map_err(|b| {
                    let b: Vec<u8> = b.into();
                    Error::Transfer(ErrorTransfer(b.into()))
                })?;
            token_addrs.push(token_addr);
            token_amts.push(amt);
        }
        self.cursor.setter(sender).set(U32::from(until));
        // Return what we made. Note: we have to return two lists here,
        // the current JSON ABI compiler can't spit out the right type
        // for this.
        Ok((token_addrs, token_amts))
    }
}

impl From<U256> for WordEmail {
    fn from(val: U256) -> Self {
        let bytes: [u8; 32] = val.to_be_bytes();
        let status = match bytes[28] {
            1 => EmailStatus::REFUNDED,
            _ => EmailStatus::RECEIVED,
        };
        WordEmail {
            refund_recipient: Address::from_slice(&bytes[0..20]),
            token_id: u32::from_be_bytes(bytes[20..24].try_into().unwrap()),
            ts_after_epoch: u32::from_be_bytes(bytes[24..28].try_into().unwrap()),
            status,
        }
    }
}

impl From<WordEmail> for U256 {
    fn from(email: WordEmail) -> Self {
        let mut bytes = [0u8; 32];
        bytes[0..20].copy_from_slice(email.refund_recipient.as_slice());
        bytes[20..24].copy_from_slice(&email.token_id.to_be_bytes());
        bytes[24..28].copy_from_slice(&email.ts_after_epoch.to_be_bytes());
        bytes[28] = email.status as u8;
        U256::from_be_bytes(bytes)
    }
}
