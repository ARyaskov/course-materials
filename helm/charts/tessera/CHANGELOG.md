# Изменения чарта tessera

Версия чарта не совпадает с версией приложения: `appVersion` меняется при
выпуске сервиса, `version` — при правке шаблонов и значений.

## 0.6.0

* Добавлены HorizontalPodAutoscaler и PodDisruptionBudget (выключены по умолчанию)
* Добавлены NetworkPolicy и условный ServiceMonitor
* Пробы переехали из отдельных полей в секцию `probes` — **ломающее изменение**,
  см. UPGRADING.md
* Добавлена `values.schema.json`
* Добавлен `preflight` Job: проверка доступности базы перед миграцией

## 0.5.2

* Миграции выполняются как `pre-upgrade` hook с уникальным именем на ревизию
* Секреты по умолчанию берутся из существующего объекта (`secrets.existingSecret`)

## 0.5.1

* Аннотация `checksum/config` перекатывает поды при смене конфигурации
* `_helpers.tpl`: разделение полного и селекторного наборов меток

## 0.5.0

* Первая версия: два Deployment из одного шаблона, Service, Ingress,
  ConfigMap, Secret, ServiceAccount
