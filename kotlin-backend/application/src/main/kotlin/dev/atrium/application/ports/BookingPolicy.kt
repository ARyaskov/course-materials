package dev.atrium.application.ports

import java.time.Duration

/** Параметры бизнес-правил броней; реализация в app-* читает их из конфигурации приложения. */
interface BookingPolicy {
    val holdTtl: Duration
    val noShowGrace: Duration
}
