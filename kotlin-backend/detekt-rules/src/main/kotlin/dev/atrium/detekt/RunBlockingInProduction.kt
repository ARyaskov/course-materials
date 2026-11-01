package dev.atrium.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtCallExpression
import org.jetbrains.kotlin.psi.KtNamedFunction
import org.jetbrains.kotlin.psi.psiUtil.getStrictParentOfType

/** runBlocking допустим в main, в src/test и в *Blocking-адаптерах для Java (team guide, урок 16.3). */
class RunBlockingInProduction(config: Config = Config.empty) : Rule(config) {
    override val issue = Issue(javaClass.simpleName, Severity.Defect, "runBlocking допустим только в main, тестах и *Blocking-адаптерах", Debt.TWENTY_MINS)

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        if (expression.calleeExpression?.text != "runBlocking") return
        val function = expression.getStrictParentOfType<KtNamedFunction>() ?: return
        val allowed = function.name == "main" || function.name.orEmpty().endsWith("Blocking") ||
            expression.containingKtFile.virtualFilePath.contains("/src/test/")
        if (!allowed) {
            report(CodeSmell(issue, Entity.from(expression), "runBlocking в ${function.name}: используйте suspend или вынесите в *Blocking-адаптер"))
        }
    }
}
