package dev.atrium.application

import dev.atrium.domain.MemberId

data class RequestContext(val requestId: String, val memberId: MemberId?)

context(req: RequestContext)
fun logFields(vararg extra: Pair<String, Any?>): Map<String, Any?> =
    mapOf("requestId" to req.requestId, "memberId" to req.memberId?.value) + extra
