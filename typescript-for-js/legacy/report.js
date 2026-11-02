// Версия отчёта до перехода на TypeScript. Работает, пока данные приходят
// в ожидаемом виде, и молча ломается, когда это не так.
//
// Что здесь не выдерживает проверки типами:
//   * duration_ms есть не у всех статусов -> NaN в среднем времени;
//   * опечатка в d.enviroment даёт undefined, а не ошибку;
//   * статусы задаются строками, и опечатка «rolledback» никем не ловится;
//   * функция принимает что угодно, включая один объект вместо массива.

import { deployments } from './deployments.js';

export function buildReport(items) {
  const byEnv = {};

  for (const d of items) {
    const env = d.environment;

    if (!byEnv[env]) {
      byEnv[env] = { total: 0, succeeded: 0, duration: 0 };
    }

    byEnv[env].total += 1;
    byEnv[env].duration += d.duration_ms;

    if (d.status === 'succeeded') {
      byEnv[env].succeeded += 1;
    }
  }

  return Object.keys(byEnv).map((env) => {
    const stats = byEnv[env];

    return {
      environment: env,
      total: stats.total,
      successRate: stats.succeeded / stats.total,
      averageDuration: stats.duration / stats.total,
    };
  });
}

export function formatReport(rows) {
  return rows
    .map(
      (row) =>
        row.environment +
        ': ' +
        row.total +
        ' деплоев, успешных ' +
        Math.round(row.successRate * 100) +
        '%, среднее время ' +
        Math.round(row.averageDuration / 1000) +
        ' с',
    )
    .join('\n');
}

if (process.argv[1]?.endsWith('report.js')) {
  console.log(formatReport(buildReport(deployments)));
}
