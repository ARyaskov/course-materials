use std::fmt;

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

use crate::errors::DomainError;

/// ISO 4217 currency codes accepted by CourseFlow.
#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum Currency {
    Usd,
    Eur,
}

impl Currency {
    pub fn as_str(&self) -> &'static str {
        match self {
            Currency::Usd => "USD",
            Currency::Eur => "EUR",
        }
    }
}

impl fmt::Display for Currency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl std::str::FromStr for Currency {
    type Err = DomainError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "USD" => Ok(Currency::Usd),
            "EUR" => Ok(Currency::Eur),
            other => {
                Err(DomainError::Validation { field: "currency", message: format!("unsupported currency {other}") })
            }
        }
    }
}

/// Amount + currency. Never a float: prices are exact decimals with two digits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Money {
    amount: Decimal,
    currency: Currency,
}

impl Money {
    pub fn new(amount: Decimal, currency: Currency) -> Result<Self, DomainError> {
        if amount.is_sign_negative() {
            return Err(DomainError::Validation { field: "price", message: "price cannot be negative".into() });
        }
        if amount.scale() > 2 {
            return Err(DomainError::Validation {
                field: "price",
                message: "price supports at most two decimal places".into(),
            });
        }
        Ok(Self { amount, currency })
    }

    pub fn free(currency: Currency) -> Self {
        Self { amount: Decimal::ZERO, currency }
    }

    pub fn amount(&self) -> Decimal {
        self.amount
    }

    pub fn currency(&self) -> Currency {
        self.currency
    }

    pub fn is_free(&self) -> bool {
        self.amount.is_zero()
    }
}

impl fmt::Display for Money {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:.2} {}", self.amount, self.currency)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal::dec;

    #[test]
    fn rejects_negative_and_too_precise() {
        assert!(Money::new(dec!(-1), Currency::Usd).is_err());
        assert!(Money::new(dec!(9.999), Currency::Usd).is_err());
        assert!(Money::new(dec!(49.90), Currency::Eur).is_ok());
    }
}
