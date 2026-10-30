package io.meterway.security;

import jakarta.inject.Singleton;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;

/**
 * Ключ вида {@code mw_live_<prefix>.<secret>}: по префиксу ищем строку в базе,
 * секрет сравниваем по хешу за постоянное время.
 */
@Singleton
public class ApiKeyHasher {

    private static final String PREFIX_MARKER = "mw_";
    private static final SecureRandom RANDOM = new SecureRandom();

    public record GeneratedKey(String presented, String prefix, String secretHash) {
    }

    public GeneratedKey generate(String environment) {
        byte[] prefixBytes = new byte[6];
        byte[] secretBytes = new byte[24];
        RANDOM.nextBytes(prefixBytes);
        RANDOM.nextBytes(secretBytes);

        String prefix = PREFIX_MARKER + environment + "_" + HexFormat.of().formatHex(prefixBytes);
        String secret = Base64.getUrlEncoder().withoutPadding().encodeToString(secretBytes);
        return new GeneratedKey(prefix + "." + secret, prefix, hash(secret));
    }

    public String hash(String secret) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(secret.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 недоступен", e);
        }
    }

    public boolean matches(String presentedSecret, String storedHash) {
        return MessageDigest.isEqual(
                hash(presentedSecret).getBytes(StandardCharsets.UTF_8),
                storedHash.getBytes(StandardCharsets.UTF_8));
    }

    /** Разбирает предъявленный ключ на префикс и секрет. Возвращает null, если формат не тот. */
    public String[] split(String presented) {
        int dot = presented.indexOf('.');
        if (dot <= 0 || dot == presented.length() - 1 || !presented.startsWith(PREFIX_MARKER)) {
            return null;
        }
        return new String[]{presented.substring(0, dot), presented.substring(dot + 1)};
    }
}
