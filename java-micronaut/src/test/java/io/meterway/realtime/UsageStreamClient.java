package io.meterway.realtime;

import io.micronaut.websocket.WebSocketSession;
import io.micronaut.websocket.annotation.ClientWebSocket;
import io.micronaut.websocket.annotation.OnMessage;
import io.micronaut.websocket.annotation.OnOpen;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Клиент живого потока для тестов.
 * <p>
 * Абстрактный класс, а не интерфейс: {@code @ClientWebSocket} требует именно его,
 * потому что клиенту нужно состояние — накопленные сообщения и сессия.
 */
@ClientWebSocket("/v1/stream/usage/{tenantId}")
public abstract class UsageStreamClient implements AutoCloseable {

    private final List<UsageUpdate> received = new CopyOnWriteArrayList<>();
    private volatile WebSocketSession session;

    @OnOpen
    void onOpen(WebSocketSession session) {
        this.session = session;
    }

    @OnMessage
    void onMessage(UsageUpdate update) {
        received.add(update);
    }

    public abstract void send(String message);

    public List<UsageUpdate> received() {
        return List.copyOf(received);
    }

    public boolean isOpen() {
        return session != null && session.isOpen();
    }
}
