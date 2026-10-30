package io.meterway.realtime;

import io.meterway.security.MeterwayPrincipal;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.authentication.Authentication;
import io.micronaut.websocket.CloseReason;
import io.micronaut.websocket.WebSocketBroadcaster;
import io.micronaut.websocket.WebSocketSession;
import io.micronaut.websocket.annotation.OnClose;
import io.micronaut.websocket.annotation.OnMessage;
import io.micronaut.websocket.annotation.OnOpen;
import io.micronaut.websocket.annotation.ServerWebSocket;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;
import java.util.function.Predicate;

/**
 * Живой поток обновлений потребления.
 * <p>
 * Подписка ограничена тенантом: предикат рассылки сравнивает атрибут сессии,
 * записанный при открытии соединения, а не значение, присланное клиентом в сообщении.
 */
@ServerWebSocket("/v1/stream/usage/{tenantId}")
@Secured("CONSOLE")
public class UsageStreamSocket {

    private static final Logger LOG = LoggerFactory.getLogger(UsageStreamSocket.class);
    private static final String TENANT_ATTRIBUTE = "meterway.tenant";

    private final WebSocketBroadcaster broadcaster;

    public UsageStreamSocket(WebSocketBroadcaster broadcaster) {
        this.broadcaster = broadcaster;
    }

    /**
     * Тенант из пути сравнивается с тенантом из аутентификации.
     * <p>
     * {@code @Secured("CONSOLE")} проверяет роль, но не принадлежность: без этой проверки
     * любой оператор подключился бы к потоку любого тенанта. Та же ошибка, что приём
     * идентификатора тенанта параметром запроса в REST, только менее заметная —
     * переменная пути выглядит как маршрут, а не как данные от клиента.
     */
    @OnOpen
    public void onOpen(String tenantId, WebSocketSession session) {
        UUID authenticated = session.getUserPrincipal()
                .filter(Authentication.class::isInstance)
                .map(Authentication.class::cast)
                .flatMap(MeterwayPrincipal::findTenantId)
                .orElse(null);

        if (authenticated == null || !authenticated.toString().equals(tenantId)) {
            LOG.warn("Отказ в подключении к потоку тенанта {}: аутентифицирован {}",
                    tenantId, authenticated);
            session.close(CloseReason.POLICY_VIOLATION);
            return;
        }
        session.put(TENANT_ATTRIBUTE, tenantId);
        LOG.debug("Открыт поток потребления для тенанта {}, сессия {}", tenantId, session.getId());
    }

    @OnMessage
    public void onMessage(String tenantId, String message, WebSocketSession session) {
        // Канал односторонний: сообщения от клиента используются только как ping.
        if ("ping".equals(message)) {
            session.sendSync("pong");
        }
    }

    @OnClose
    public void onClose(String tenantId, WebSocketSession session) {
        LOG.debug("Закрыт поток потребления тенанта {}, сессия {}", tenantId, session.getId());
    }

    /** Рассылает обновление всем сессиям указанного тенанта. */
    public void publish(String tenantId, UsageUpdate update) {
        broadcaster.broadcastAsync(update, forTenant(tenantId));
    }

    private Predicate<WebSocketSession> forTenant(String tenantId) {
        return session -> session.get(TENANT_ATTRIBUTE, String.class)
                .map(tenantId::equals)
                .orElse(false);
    }
}
