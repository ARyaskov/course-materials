package dev.atrium.detekt

import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSet
import io.gitlab.arturbosch.detekt.api.RuleSetProvider

class AtriumRuleSetProvider : RuleSetProvider {
    override val ruleSetId: String = "atrium"

    override fun instance(config: Config): RuleSet = RuleSet(ruleSetId, listOf(RunBlockingInProduction(config), SwallowedCancellation(config), DataClassEntity(config)))
}
