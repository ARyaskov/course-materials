# Номера ошибок Waybill (THROW 50xxx) и их отображение в API

| Номер | Где | Смысл | HTTP |
| --- | --- | --- | --- |
| 50001 | ship.usp_PatchShipmentAttributes, служебные | Отправление не найдено | 404 |
| 50010 | demo.usp_SearchShipments | Недопустимый столбец сортировки | 400 |
| 50011 | demo.usp_SearchShipments | Недопустимая страница | 400 |
| 50020 | 055_constraints_extra.sql | Неизвестный часовой пояс в ref.Region (проверка seed) | — |
| 50030 | ops.usp_ValidateWebhook | Тело webhook — не JSON | 400 |
| 50031 | ops.usp_ValidateWebhook, usp_IngestTrackingEvents, usp_CreateShipment | Неизвестный или неактивный перевозчик | 404 |
| 50032 | ops.usp_ValidateWebhook | Структура webhook не соответствует формату перевозчика | 422 |
| 50033 | ops.usp_ValidateWebhook | В webhook нет ни одного события с корректным временем | 422 |
| 50040 | ship.usp_PatchShipmentAttributes | Патч должен быть JSON-объектом | 400 |
| 50050 | ship.usp_CreateShipment, crm.usp_UpsertMerchantSetting | Неизвестный или неактивный магазин | 404 |
| 50051 | ship.usp_CreateShipment | Трек-номер не соответствует формату перевозчика | 422 |
| 50061 | ship.usp_CreateShipmentSerialized | Не удалось получить прикладную блокировку заказа за таймаут | 503 / retry |
| 50070 | ship.usp_UpdateShipmentIfMatch | Строка изменена другим пользователем (RowVer не совпал) | 412 |
| 50080 | ops.usp_EmitOutbox | Событие outbox записывается только внутри транзакции с изменением данных | 500 (ошибка программирования) |
| 50081 | ops.usp_DequeueOutbox | Неверные PartitionCount/Partition | 500 (конфигурация) |
| 50082 | ops.usp_OutboxTargetActivation | Ошибка внутреннего потребителя (END CONVERSATION WITH ERROR) | — |
| 50090 | тесты нормализации | Функция нормализации вернула неожиданный результат | — |
| 50095 | ship.usp_ListShipmentsSorted | Столбец сортировки не из белого списка | 400 |
| 50096 | ship.usp_ListShipmentsSorted | Направление сортировки не ASC/DESC | 400 |
| 50100 | ops.usp_BackupDatabase | Неверный тип бэкапа (FULL/DIFF/LOG) | — |
| 50110 | bill.usp_GenerateInvoice | Счёт уже выставлен — пересчёт невозможен | 409 |
| 50111 | bill.usp_IssueInvoice | Счёт не найден или не черновик | 409 |

Системные ошибки, которые API переводит сам:

| Номер | Смысл | HTTP |
| --- | --- | --- |
| 2627 / 2601 | Нарушение уникальности: `UQ_Shipment_Merchant_Order` → существующий заказ; `UQ_Shipment_Carrier_Tracking` → трек-номер занят | 409 |
| 547 | Нарушение CHECK/FK (имя ограничения в тексте) | 422 |
| 33504 | BLOCK-предикат RLS: запись строки чужого арендатора (`sec.MerchantIsolation`) | 403 |
| 229 / 230 | Нет прав на объект/столбец (роль `waybill_api` вне разрешённого набора) | 403 (ошибка конфигурации) |
| 1205 | Deadlock victim — повторить операцию | retry |
| 13535 | Temporal: две транзакции обновили одну строку `ship.Shipment`, и у позже зафиксированной время начала раньше `ValidFrom` текущей версии (горячие строки, глава 8/11) | retry (как 1205) |
| -2 (клиент) | Таймаут команды | 504 / retry |
