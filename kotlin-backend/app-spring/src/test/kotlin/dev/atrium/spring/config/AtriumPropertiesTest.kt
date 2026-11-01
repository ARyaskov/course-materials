package dev.atrium.spring.config

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.boot.context.properties.bind.BindException
import org.springframework.boot.context.properties.bind.Binder
import org.springframework.boot.context.properties.source.MapConfigurationPropertySource
import java.time.Duration

/** Связывание конфигурации без Spring-контекста: Binder напрямую — миллисекунды на тест. */
class AtriumPropertiesTest {
    private fun bind(vararg pairs: Pair<String, String>): AtriumProperties =
        Binder(MapConfigurationPropertySource(mapOf(*pairs))).bind("atrium", AtriumProperties::class.java).get()

    private val required = arrayOf(
        "atrium.paygate.base-url" to "http://paygate", "atrium.paygate.api-key" to "k",
        "atrium.notify.base-url" to "http://notify", "atrium.notify.api-key" to "k",
    )

    @Test
    fun `hold ttl is parsed with unit`() {
        val props = bind(*required, "atrium.booking.hold-ttl" to "30m")
        assertEquals(Duration.ofMinutes(30), props.booking.holdTtl)
    }

    @Test
    fun `hold ttl without unit is rejected by init`() {
        val e = assertThrows<BindException> { bind(*required, "atrium.booking.hold-ttl" to "150") }
        assertTrue("hold-ttl" in (e.cause?.message ?: e.message ?: ""))
    }

    @Test
    fun `notify batch size outside range is rejected`() {
        assertThrows<BindException> { bind(*required, "atrium.notify.batch-size" to "500") }
    }
}
