package dev.atrium.domain

/** PII, которая не должна попадать в логи через toString() data class-ов (урок 14.1). */
@JvmInline
value class Redacted(val value: String) {
    override fun toString(): String = "***"
}
