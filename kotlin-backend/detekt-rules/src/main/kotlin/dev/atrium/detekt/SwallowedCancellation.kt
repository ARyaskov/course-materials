package dev.atrium.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtCatchClause

/** catch (e: Exception/Throwable) в suspend-коде без проброса CancellationException — проглоченная отмена (уроки 6.4, 16.3). */
class SwallowedCancellation(config: Config = Config.empty) : Rule(config) {
    override val issue = Issue(javaClass.simpleName, Severity.Defect, "catch Exception без `if (e is CancellationException) throw e` проглатывает отмену", Debt.TEN_MINS)

    override fun visitCatchClause(catchClause: KtCatchClause) {
        super.visitCatchClause(catchClause)
        val type = catchClause.catchParameter?.typeReference?.text ?: return
        if (type !in setOf("Exception", "Throwable")) return
        val body = catchClause.catchBody?.text.orEmpty()
        if ("CancellationException" !in body && "runCatchingCancellable" !in body) {
            report(CodeSmell(issue, Entity.from(catchClause), "перебросьте CancellationException или используйте runCatchingCancellable"))
        }
    }
}
