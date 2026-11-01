package dev.atrium.domain

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency

/**
 * Денежная сумма в одной валюте. Масштаб фиксируется по валюте (RUB, EUR — 2 знака),
 * поэтому 10.5 и 10.50 равны, а сложение сумм в разных валютах — ошибка программиста.
 */
data class Money(val amount: BigDecimal, val currency: Currency) {
    init {
        require(amount.signum() >= 0) { "Money amount must not be negative: $amount" }
        require(amount.scale() <= currency.defaultFractionDigits) {
            "Money amount $amount has more fraction digits than ${currency.currencyCode} allows"
        }
    }

    operator fun plus(other: Money): Money {
        require(currency == other.currency) { "Currency mismatch: $currency vs ${other.currency}" }
        return copy(amount = amount + other.amount)
    }

    operator fun times(factor: BigDecimal): Money =
        copy(amount = (amount * factor).setScale(currency.defaultFractionDigits, RoundingMode.HALF_EVEN))

    operator fun times(factor: Int): Money = times(BigDecimal(factor))

    override fun equals(other: Any?): Boolean =
        other is Money && currency == other.currency && amount.compareTo(other.amount) == 0

    override fun hashCode(): Int = 31 * currency.hashCode() + amount.stripTrailingZeros().hashCode()

    override fun toString(): String = "${amount.setScale(currency.defaultFractionDigits)} ${currency.currencyCode}"

    companion object {
        val RUB: Currency = Currency.getInstance("RUB")

        fun rub(amount: String): Money = Money(BigDecimal(amount), RUB)
        fun zero(currency: Currency): Money = Money(BigDecimal.ZERO.setScale(currency.defaultFractionDigits), currency)
    }
}
