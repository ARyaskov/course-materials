package dev.atrium.application.testing

import tools.jackson.databind.JsonNode
import tools.jackson.databind.json.JsonMapper
import tools.jackson.module.kotlin.KotlinModule

data class ContractRequest(val method: String, val path: String, val headers: Map<String, String> = emptyMap(), val body: JsonNode? = null)
data class ContractCase(val name: String, val request: ContractRequest, val expectedStatus: Int, val expectedBody: JsonNode? = null)

/** Общие JSON-случаи из contract/v1/ для параметризованных тестов app-spring и app-ktor. */
object ContractCases {
    private val mapper = JsonMapper.builder().addModule(KotlinModule.Builder().build()).build()

    fun load(version: String = "v1"): List<ContractCase> {
        val index = ContractCases::class.java.getResource("/contract/$version/index.txt")?.readText().orEmpty()
        return index.lines().filter { it.isNotBlank() }.map { file ->
            val resource = requireNotNull(ContractCases::class.java.getResourceAsStream("/contract/$version/$file"))
            val node = resource.use { mapper.readTree(it) }
            ContractCase(
                name = file.removeSuffix(".json"),
                request = mapper.treeToValue(node["request"], ContractRequest::class.java),
                expectedStatus = node["expectedStatus"].asInt(),
                expectedBody = node["expectedBody"],
            )
        }
    }
}

/** Структурное сравнение с масками: "<uuid>" — любой UUID, "<instant>" — любой ISO-8601. Порядок ключей не важен, массивов — важен. */
fun JsonNode.matchesExpected(expected: JsonNode): Boolean = when {
    expected.isString && expected.asString() == "<uuid>" -> isString && Regex("[0-9a-f-]{36}").matches(asString())
    expected.isString && expected.asString() == "<instant>" -> isString && Regex("\\d{4}-\\d{2}-\\d{2}T.*Z").matches(asString())
    expected.isObject -> isObject && expected.properties().all { (k, v) -> get(k)?.matchesExpected(v) == true }
    expected.isArray -> isArray && size() == expected.size() && (0 until size()).all { get(it).matchesExpected(expected[it]) }
    else -> this == expected
}
