import { DomainException } from '../errors/domain-error';

export type Currency = 'USD' | 'EUR';

/**
 * Money as an immutable value object stored in integer cents — never floats.
 * Invalid states (non-integer, negative, currency mismatch) are unrepresentable.
 */
export class Money {
  private constructor(
    public readonly amountCents: number,
    public readonly currency: Currency,
  ) {}

  static of(amountCents: number, currency: Currency): Money {
    if (!Number.isInteger(amountCents)) {
      throw new DomainException({ code: 'INVALID_MONEY_AMOUNT' });
    }
    if (amountCents < 0) {
      throw new DomainException({ code: 'NEGATIVE_MONEY_AMOUNT' });
    }
    return new Money(amountCents, currency);
  }

  static zero(currency: Currency): Money {
    return new Money(0, currency);
  }

  add(other: Money): Money {
    if (other.currency !== this.currency) {
      throw new DomainException({ code: 'CURRENCY_MISMATCH' });
    }
    return new Money(this.amountCents + other.amountCents, this.currency);
  }

  isZero(): boolean {
    return this.amountCents === 0;
  }
}
