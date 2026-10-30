package io.meterway.event;

import io.micronaut.context.event.ShutdownEvent;
import io.micronaut.runtime.event.annotation.EventListener;
import jakarta.inject.Singleton;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Флаг остановки для длинных фоновых задач.
 * <p>
 * Задача, обрабатывающая сотни тенантов, не должна начинать следующего, когда приложение
 * останавливается: недоделанное подхватит следующий запуск на другом поде, потому что
 * закрытие периода идемпотентно. Без проверки задача либо успеет в отведённое время,
 * либо будет убита SIGKILL посреди работы.
 */
@Singleton
public class ShutdownState {

    private final AtomicBoolean stopping = new AtomicBoolean();

    @EventListener
    void onShutdown(ShutdownEvent event) {
        stopping.set(true);
    }

    public boolean isStopping() {
        return stopping.get();
    }
}
