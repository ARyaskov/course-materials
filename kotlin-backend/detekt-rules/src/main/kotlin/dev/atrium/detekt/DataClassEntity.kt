package dev.atrium.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtClass

/** data class в пакете domain с полем id — сущность со структурным equals: запрещено team guide (урок 16.3). */
class DataClassEntity(config: Config = Config.empty) : Rule(config) {
    override val issue = Issue(javaClass.simpleName, Severity.Maintainability, "сущность с id не должна быть data class", Debt.TWENTY_MINS)

    override fun visitClass(klass: KtClass) {
        super.visitClass(klass)
        if (!klass.isData()) return
        if (!klass.containingKtFile.packageFqName.asString().endsWith(".domain")) return
        val hasId = klass.primaryConstructorParameters.any { it.name == "id" && it.hasValOrVar() }
        if (hasId) report(CodeSmell(issue, Entity.from(klass), "${klass.name}: сущность — class с equals по id, переходы — методами, не copy"))
    }
}
