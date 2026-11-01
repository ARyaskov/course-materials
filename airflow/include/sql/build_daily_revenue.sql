-- Идемпотентная сборка витрины дневной выручки за {{ params.run_date }}.
-- Перезапись партиции: сначала удалить за дату, затем вставить заново.
-- Так повторный прогон (повтор, backfill) приводит партицию к нужному
-- состоянию и не плодит дубли.

DELETE FROM marts.daily_revenue
WHERE d = DATE '{{ params.run_date }}';

INSERT INTO marts.daily_revenue (d, orders, revenue)
SELECT d,
       count(*)    AS orders,
       sum(amount) AS revenue
FROM staging.orders
WHERE d = DATE '{{ params.run_date }}'
GROUP BY d;
