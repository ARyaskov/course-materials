// Печатает фикстуры в том виде, в каком их отдаёт HTTP API.
// Запуск: node scripts/fixtures.js > deployments.json
//
// Node 24 умеет импортировать .ts напрямую, поэтому обычному JS-скрипту
// доступны те же данные и те же функции преобразования, что и приложению.

import { fromDeployment } from '../src/api/mappers.ts';
import { fixtureDeployments } from '../src/fixtures/deployments.ts';

const payload = {
  data: fixtureDeployments.map(fromDeployment),
  meta: { total: fixtureDeployments.length, limit: fixtureDeployments.length, offset: 0 },
};

process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
