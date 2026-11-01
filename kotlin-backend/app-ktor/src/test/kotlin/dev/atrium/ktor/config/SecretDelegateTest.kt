package dev.atrium.ktor.config

import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path

class SecretDelegateTest {
    @Test
    fun `secret is read from secrets directory when env is absent`(@TempDir dir: Path) {
        Files.writeString(dir.resolve("atrium_test_secret_xyz"), "s3cr3t\n")
        val holder = object { val key: String by secret("ATRIUM_TEST_SECRET_XYZ", secretsDir = dir) }
        holder.key shouldBe "s3cr3t"
    }
}
