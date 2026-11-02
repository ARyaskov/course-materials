# tessera

Сервис продажи и валидации билетов на события: HTTP API и фоновый обработчик
просроченных броней.

## Установка

```bash
helm upgrade --install tessera oci://ghcr.io/tessera-app/charts/tessera \
  --version 0.6.0 -n tessera --create-namespace -f my-values.yaml
```

## Что нужно снаружи

* PostgreSQL 16+, доступный из кластера
* Redis 7+
* Secret с ключами `TESSERA_DATABASE_DSN`, `TESSERA_REDIS_PASSWORD`,
  `TESSERA_TICKET_SIGN_KEY` — его имя передаётся в `secrets.existingSecret`
* Ingress-контроллер, если `ingress.enabled: true`

Чарт не создаёт базу и кэш: они живут снаружи и управляются отдельно.

## Основные параметры

| Ключ | По умолчанию | Смысл |
| --- | --- | --- |
| `secrets.existingSecret` | `""` | Имя существующего Secret; обязателен вне dev |
| `secrets.create` | `true` | Создать Secret из значений — только для стендов |
| `image.repository` | `ghcr.io/tessera-app/tessera` | Образ приложения |
| `image.tag` | `""` | Пусто — берётся `appVersion` |
| `api.replicaCount` | `2` | Реплики API; не используется при `autoscaling.enabled` |
| `worker.enabled` | `true` | Фоновый обработчик броней |
| `ingress.hosts` | `tessera.localtest.me` | Список хостов и путей |
| `migrations.enabled` | `true` | Миграции как `pre-upgrade` Job |
| `autoscaling.enabled` | `false` | HPA для API |

Полный список — `helm show values`, ограничения типов — `values.schema.json`.

## Проверка после установки

```bash
helm test tessera -n tessera
kubectl get pods -n tessera -l app.kubernetes.io/instance=tessera
```

## Обновление

Миграции выполняются как `pre-upgrade` hook до обновления подов. Перед выкладкой
убедитесь, что предыдущая версия кода совместима с новой схемой — иначе откат
будет невозможен.
