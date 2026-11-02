import { fixtureDeployments } from '#fixtures/deployments.ts';
import { renderReport } from '#reports/report.ts';
import { summarize } from '#reports/summary.ts';

/**
 * Минимальная точка входа из главы 2: данные — отчёт — вывод.
 * Полноценный CLI со всеми командами живёт в src/cli/main.ts.
 */
const summary = summarize(fixtureDeployments);

console.log(renderReport(summary));
