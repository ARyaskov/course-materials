import { Money } from './money';
import { DomainException } from '../errors/domain-error';

describe('Money', () => {
  it('creates a valid amount', () => {
    const m = Money.of(4900, 'USD');
    expect(m.amountCents).toBe(4900);
    expect(m.currency).toBe('USD');
    expect(m.isZero()).toBe(false);
  });

  it('zero() is zero', () => {
    expect(Money.zero('EUR').isZero()).toBe(true);
  });

  it('rejects non-integer amounts', () => {
    expect(() => Money.of(10.5, 'USD')).toThrow(DomainException);
  });

  it('rejects negative amounts', () => {
    expect(() => Money.of(-1, 'USD')).toThrow(DomainException);
  });

  it('adds amounts of the same currency', () => {
    const sum = Money.of(100, 'USD').add(Money.of(250, 'USD'));
    expect(sum.amountCents).toBe(350);
  });

  it('refuses to add mismatched currencies', () => {
    expect(() => Money.of(100, 'USD').add(Money.of(100, 'EUR'))).toThrow(DomainException);
  });
});
