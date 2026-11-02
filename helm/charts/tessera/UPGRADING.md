# Обновление чарта tessera

## С 0.5.x на 0.6.0

### Пробы переехали в секцию probes

Было:

```yaml
api:
  readinessPeriodSeconds: 5
  readinessFailureThreshold: 2
  livenessPeriodSeconds: 10
```

Стало:

```yaml
api:
  probes:
    readinessProbe:
      httpGet:
        path: /readyz
        port: admin
      periodSeconds: 5
      failureThreshold: 2
    livenessProbe:
      httpGet:
        path: /healthz
        port: admin
      periodSeconds: 10
```

Старые ключи игнорируются, и без правки применятся значения по умолчанию.
Схема значений с `additionalProperties` для секции `image` поймает опечатки,
но старые ключи проб — нет.

### Добавлена values.schema.json

Значения теперь проверяются по схеме. Типичные находки при первом обновлении:
числа, записанные строками, и уровни логирования вне набора
`debug | info | warn | error`.

### Порядок обновления

1. Обновить файлы значений всех окружений.
2. `helm template` на каждом профиле — схема должна пройти.
3. `helm diff upgrade` — проверить, что пробы получились те же.
4. Обновить dev, затем staging, затем production.

Ломающих изменений в именах ресурсов и селекторах нет: обновление
существующих релизов проходит без пересоздания объектов.
