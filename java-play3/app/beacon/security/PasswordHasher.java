package beacon.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.security.spec.KeySpec;
import java.util.Base64;
import java.util.HexFormat;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.inject.Singleton;

/**
 * Хеширование паролей администраторов (PBKDF2) и секретов API-ключей (SHA-256).
 *
 * <p>Пароль пользователя и машинный ключ — разные задачи: пароль короткий и угадываемый,
 * поэтому нужен медленный KDF; API-ключ содержит 128 бит энтропии, и быстрый хеш достаточен.
 */
@Singleton
public class PasswordHasher {

    private static final int ITERATIONS = 210_000;
    private static final int KEY_LENGTH_BITS = 256;
    private static final SecureRandom RANDOM = new SecureRandom();

    public String hashPassword(String password) {
        byte[] salt = new byte[16];
        RANDOM.nextBytes(salt);
        byte[] hash = pbkdf2(password, salt);
        return "pbkdf2$%d$%s$%s".formatted(
                ITERATIONS,
                Base64.getEncoder().encodeToString(salt),
                Base64.getEncoder().encodeToString(hash));
    }

    public boolean verifyPassword(String password, String stored) {
        String[] parts = stored.split("\\$");
        if (parts.length != 4 || !"pbkdf2".equals(parts[0])) {
            return false;
        }
        byte[] salt = Base64.getDecoder().decode(parts[2]);
        byte[] expected = Base64.getDecoder().decode(parts[3]);
        byte[] actual = pbkdf2(password, salt, Integer.parseInt(parts[1]), expected.length * 8);
        return MessageDigest.isEqual(expected, actual);
    }

    /** Хеш секретной части API-ключа. Сравнение всегда через MessageDigest.isEqual. */
    public String hashApiSecret(String secret) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(secret.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public boolean verifyApiSecret(String secret, String storedHash) {
        return MessageDigest.isEqual(
                hashApiSecret(secret).getBytes(StandardCharsets.UTF_8),
                storedHash.getBytes(StandardCharsets.UTF_8));
    }

    private byte[] pbkdf2(String password, byte[] salt) {
        return pbkdf2(password, salt, ITERATIONS, KEY_LENGTH_BITS);
    }

    private byte[] pbkdf2(String password, byte[] salt, int iterations, int keyLengthBits) {
        try {
            KeySpec spec = new PBEKeySpec(password.toCharArray(), salt, iterations, keyLengthBits);
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException("не удалось вычислить PBKDF2", e);
        }
    }
}
