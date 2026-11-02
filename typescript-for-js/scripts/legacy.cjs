// Скрипт из времён CommonJS: остался в проекте как есть.
// ESM-модули подключаются из него через динамический import().
//
// Запуск: node scripts/legacy.cjs

'use strict';

const { basename } = require('node:path');

async function main() {
  const { buildReport, formatReport } = await import('../legacy/report.js');
  const { deployments } = await import('../legacy/deployments.js');

  console.log(`[${basename(__filename)}] отчёт старой версии:`);
  console.log(formatReport(buildReport(deployments)));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
