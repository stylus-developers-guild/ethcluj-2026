// In this example, senders of emails must pay the token that recipients
// have indicated that they receive. The recipients must indicate that
// they've received the emails from before until a buffer amount, at
// which point users can not send emails to the recipient. If the
// recipient does not claim their email inbox after a window has passed,
// the original senders can claim a refund, and the recipient will remain
// full. NOT FOR PRODUCTION: Does not check erc20 return values.

#![cfg_attr(not(any(test, feature = "export-abi")), no_std)]

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
    pub token_asks: StorageMap<Address, StorageVec<StorageU256>>,

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
    error ErrorEmailTooBackedUp();
    error ErrorTooManyEmails();
    error ErrorTransfer(bytes);
    error ErrorPastDeadline();
    error ErrorTransferFrom(bytes);
    error ErrorNotPastDeadline();
    error ErrorAlreadyRefunded();
    error ErrorTooManyTokens();
    error ErrorNotYourEmail();
    error ErrorEmailNonexistent();
    error ErrorAlreadyRead();
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
    TooManyEmails(ErrorTooManyEmails),
    EmailTooBackedUp(ErrorEmailTooBackedUp),
    Transfer(ErrorTransfer),
    PastDeadline(ErrorPastDeadline),
    TransferFrom(ErrorTransferFrom),
    NotPastDeadline(ErrorNotPastDeadline),
    AlreadyRefunded(ErrorAlreadyRefunded),
    TooManyTokens(ErrorTooManyTokens),
    NotYourEmail(ErrorNotYourEmail),
    EmailNonexistent(ErrorEmailNonexistent),
    AlreadyRead(ErrorAlreadyRead),
}

impl core::fmt::Debug for Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::ContractNotConfigured(_) => write!(f, "ContractNotConfigured"),
            Self::ContractTooOld(_) => write!(f, "ContractTooOld"),
            Self::TokenDisabled(_) => write!(f, "TokenDisabled"),
            Self::NotEnoughToken(_) => write!(f, "NotEnoughToken"),
            Self::TooManyEmails(_) => write!(f, "TooManyEmails"),
            Self::EmailTooBackedUp(_) => write!(f, "EmailTooBackedUp"),
            Self::Transfer(_) => write!(f, "Transfer"),
            Self::PastDeadline(_) => write!(f, "PastDeadline"),
            Self::TransferFrom(_) => write!(f, "TransferFrom"),
            Self::NotPastDeadline(_) => write!(f, "NotPastDeadline"),
            Self::AlreadyRefunded(_) => write!(f, "AlreadyRefunded"),
            Self::TooManyTokens(_) => write!(f, "TooManyTokens"),
            Self::NotYourEmail(_) => write!(f, "NotYourEmail"),
            Self::EmailNonexistent(_) => write!(f, "EmailNonexistent"),
            Self::AlreadyRead(_) => write!(f, "AlreadyRead"),
        }
    }
}

#[public]
impl Storage {
    /// Enable a token for a recipient with a given ask amount.
    /// The token_id must be nonzero (0 is reserved as "disabled").
    pub fn enable_token(&mut self, token_addr: Address, ask: U256) -> Result<U32, Error> {
        let sender = self.vm().msg_sender();
        let mut token_id = U32::from(self.token_asks.get(sender).len());
        // We start all token ids from 1 so we can detect they're not set later:
        if token_id.is_zero() {
            token_id += U32::ONE;
            unsafe {
                // We start from 1 from this, so 0 is the sign that something isn't set:
                self.token_asks.setter(sender).set_len(1);
            }
        }
        self.ids_to_tokens
            .setter(sender)
            .setter(token_id)
            .set(token_addr);
        if !token_addr.is_zero() {
            if token_id == U32::MAX {
                // Final sanity check since the state will unwind if this is bad.
                // Check that we're not about to exceed the limit of tokens that
                // a user can have:
                return Err(Error::TooManyTokens(ErrorTooManyTokens {}));
            }
            // Set the token to something if it's not set to zero:
            self.token_asks.setter(sender).push(ask);
            self.enabled_tokens
                .setter(sender)
                .setter(token_addr)
                .set(token_id);
        }
        Ok(token_id)
    }

    /// Estimate the amount needed for a email to be sent to a recipient.
    pub fn estimate_amt_needed(
        &self,
        recipient: Address,
        token_addr: Address,
    ) -> Result<U256, Error> {
        let token_id = self.enabled_tokens.getter(recipient).get(token_addr);
        if token_id.is_zero() {
            return Err(Error::TokenDisabled(ErrorTokenDisabled {}));
        }
        Ok(self.token_asks.getter(recipient).get(token_id).unwrap())
    }

    pub fn send_email(
        &mut self,
        recipient: Address,
        refund_recipient: Address,
        token_addr: Address,
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
        let token_id = self.enabled_tokens.getter(recipient).get(token_addr);
        if token_id.is_zero() {
            // The first value in this vector is always unset so we can make
            // use of this check.
            return Err(Error::TokenDisabled(ErrorTokenDisabled {}));
        }
        // The minimum token amount is the amount we'll actually take from
        // the user in the token they provided.
        let min_amt = self.token_asks.getter(recipient).get(token_id).unwrap();
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
        // Check whether the oldest unread email has been waiting for too long:
        if unread_emails > 0 {
            // The first unread email is at index `cursor` (0-based).
            let WordEmail { ts_after_epoch, .. } = self
                .received_emails
                .setter(recipient)
                .get(cursor)
                .unwrap()
                .into();
            let time_since_epoch = current_ts - ts_epoch;
            let is_past_deadline = time_since_epoch > ts_after_epoch as u64 + UNREAD_WINDOW;
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
        let token_id_u32 = token_id.as_limbs()[0] as u32;
        let email = WordEmail {
            refund_recipient,
            token_id: token_id_u32,
            ts_after_epoch,
            status: EmailStatus::RECEIVED,
        };
        self.received_emails.setter(recipient).push(email.into());
        // And take the amount from the user! This is not reentrant
        // thanks to security guarantees from Stylus.
        let config = Call::new_mutating(self);
        let sender = self.vm().msg_sender();
        let contract = self.vm().contract_address();
        IERC20::new(token_addr)
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
        // This needs to be implemented in a way that advances the cursor
        // while simultaneously not reading refunded messages. The user
        // needs to receive the token that they were allocated.
        todo!()
    }

    /// Refund an email that has passed the deadline. The original sender
    /// can call this to reclaim their tokens if the recipient hasn't read
    /// the email within the UNREAD_WINDOW.
    pub fn refund(&mut self, recipient: Address, email_index: u32) -> Result<U256, Error> {
        todo!()
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
