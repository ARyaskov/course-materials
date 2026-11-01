package dev.atrium.spring.config

import dev.atrium.spring.adapters.BookingEventListener
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.springframework.aop.support.AopUtils
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class ProxyingTest(@Autowired private val listener: BookingEventListener) {
    @Test
    fun `transactional listener is proxied`() {
        assertTrue(AopUtils.isAopProxy(listener), "expected CGLIB proxy, got ${listener.javaClass.name}")
    }
}
