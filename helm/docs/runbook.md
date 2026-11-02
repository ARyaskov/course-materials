# Runbook Tessera

Порядок разбора — сверху вниз. Подставьте свой неймспейс и имя релиза.

## Выкладка провалилась

1. `helm history tessera -n <ns> --max 5`
2. Сервис работает? `kubectl get pods -n <ns> -l app.kubernetes.io/instance=tessera`
   * работает → времени достаточно, разбираться спокойно
   * не работает → сначала восстановить: `helm rollback tessera -n <ns> --wait`
3. Что изменилось:
   `diff <(helm get manifest tessera -n <ns> --revision N) <(helm get manifest tessera -n <ns> --revision N+1)`
4. Почему не поднялось:
   * `kubectl describe pod <pod> -n <ns>` — если под не дошёл до Running
   * `kubectl logs <pod> -n <ns> --previous` — если дошёл и упал
   * `kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20`
5. Записать причину в описание следующей ревизии: `--description "INC-NNN: ..."`

## Релиз застрял в pending-*

1. Убедиться, что пайплайн не работает с релизом (журнал CI, чат команды).
2. `kubectl get secret -n <ns> -l owner=helm -o custom-columns='NAME:.metadata.name,STATUS:.metadata.labels.status,AGE:.metadata.creationTimestamp'`
3. `kubectl get pods,deploy -n <ns> -l app.kubernetes.io/instance=tessera` — фактическое состояние.
4. `kubectl patch secret sh.helm.release.v1.tessera.vN -n <ns> --type merge -p '{"metadata":{"labels":{"status":"failed"}}}'`
5. `helm rollback tessera -n <ns> --wait --timeout 15m`

## Миграция упала

1. `kubectl logs job/tessera-migrate-<revision> -n <ns>`
2. Состояние схемы: `SELECT version, dirty FROM schema_migrations;`
3. Учебный `/app/migrate up` применяет каждую миграцию и её номер в одной транзакции.
   При ошибке изменения этой миграции откатываются; устраните причину и повторите
   обновление. Не помечайте неприменённую миграцию выполненной вручную.
4. Поды приложения при этом не обновлялись: сервис работает на старой версии.

## Сервис недоступен, выкладки не было

1. `kubectl get pods -n <ns>` — статусы и счётчик RESTARTS.
2. В отдельном терминале: `kubectl port-forward deploy/tessera-api -n <ns> 19090:9090`,
   затем `curl -fsS localhost:19090/readyz` — какая зависимость отвалилась.
   В distroless-образе нет shell и wget.
3. `kubectl get endpointslices -l kubernetes.io/service-name=tessera-api -n <ns>` — есть ли адреса.
4. Логи Ingress-контроллера.
5. Состояние PostgreSQL и Redis.

## Конфликт владения полями

```
Error: UPGRADE FAILED: Apply failed with 1 conflict: conflict with
"horizontal-pod-autoscaler": .spec.replicas
```

1. Кто ещё претендует:
   `kubectl get deploy tessera-api -n <ns> --show-managed-fields -o json | jq -r '.metadata.managedFields[] | select(.fieldsV1["f:spec"]["f:replicas"]) | .manager'`
2. Убрать поле у того, кто им владеть не должен. `--force-conflicts` — крайняя мера.

## Откат

```bash
helm history tessera -n <ns>
helm rollback tessera <revision> -n <ns> --wait --timeout 15m
helm test tessera -n <ns> --logs
```

Откат не возвращает схему базы. Перед выкладкой с миграцией должен быть ответ
на вопрос: работает ли предыдущая версия кода с новой схемой.
