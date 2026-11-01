package dev.atrium.spring.api

import dev.atrium.domain.MemberId

/** Текущий участник из JWT (урок 10.7). До появления security — тестовый резолвер с фиксированным id. */
data class MemberPrincipal(val memberId: MemberId, val roles: Set<String> = emptySet())
