package beacon.security;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PasswordHasherTest {

    private final PasswordHasher hasher = new PasswordHasher();

    @Test
    public void passwordRoundTrip() {
        String stored = hasher.hashPassword("beacon-admin");

        assertTrue(hasher.verifyPassword("beacon-admin", stored));
        assertFalse(hasher.verifyPassword("beacon-admi", stored));
    }

    @Test
    public void demoCredentialsFromEvolutionAreValid() {
        String stored = "pbkdf2$210000$AAECAwQFBgcICQoLDA0ODw==$71vAm1qrhvkJ/QTPv1dx7yp0IvQhkkF83JPnmK/gscs=";

        assertTrue(hasher.verifyPassword("beacon-admin", stored));
    }

    @Test
    public void apiSecretHashMatchesDemoKey() {
        String stored = "3eb1bd439947eb762998e566ccc2e099c791118b2f40579cc4f7da2b5061b7f9";

        assertTrue(hasher.verifyApiSecret("0123456789abcdef0123456789abcdef", stored));
        assertFalse(hasher.verifyApiSecret("wrong", stored));
    }
}
