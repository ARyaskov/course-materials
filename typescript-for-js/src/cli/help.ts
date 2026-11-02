import { DEPLOYMENT_STATUSES } from '#domain/deployment-status.ts';
import { ENVIRONMENTS } from '#domain/environment.ts';

export const HELP_TEXT = `Shipyard — панель релизов и деплоев

Использование:
  shipyard [команда] [опции]

Команды:
  status            сводка по деплоям (по умолчанию)
  show <id>         один деплой по идентификатору, например dep_001
  serve             HTTP-сервер с JSON API и статикой доски
  help              эта справка

Опции:
  --env=<env>       окружение: ${ENVIRONMENTS.join(' | ')}
  --status=<st>     статус: ${DEPLOYMENT_STATUSES.join(' | ')}
  --author=<name>   подстрока имени автора или инициатора
  --limit=<n>       сколько записей показать (по умолчанию 20)
  --port=<n>        порт для команды serve
  --json            машиночитаемый вывод
  -h, --help        показать справку

Переменные окружения:
  SHIPYARD_SOURCE       fixtures | http
  SHIPYARD_API_URL      базовый URL внешнего API
  SHIPYARD_TIMEOUT_MS   таймаут запроса
  SHIPYARD_RETRIES      число повторов
  SHIPYARD_CACHE_TTL_MS время жизни кеша
  SHIPYARD_LOG_LEVEL    debug | info | warn | error
  PORT                  порт HTTP-сервера
`;
