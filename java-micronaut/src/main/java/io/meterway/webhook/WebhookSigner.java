package io.meterway.webhook;

import jakarta.inject.Singleton;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.HexFormat;

/**
 * Подпись исходящего вебхука.
 * <p>
 * В подпись входит метка времени: без неё перехваченный запрос можно переиграть
 * когда угодно, и получатель этого не заметит.
 */
@Singleton
public class WebhookSigner {

    private static final String ALGORITHM = "HmacSHA256";

    public String sign(String secret, long timestampSeconds, String body) {
        String payload = timestampSeconds + "." + body;
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), ALGORITHM));
            String digest = HexFormat.of().formatHex(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
            return "t=%d,v1=%s".formatted(timestampSeconds, digest);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Не удалось подписать вебхук", e);
        }
    }
}
