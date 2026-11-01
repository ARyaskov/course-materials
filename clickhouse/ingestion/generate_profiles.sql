-- Pulse: генерация профилей и истории тарифов для 1000 пользователей симулятора (глава 8).
-- Около трети пользователей сменили тариф через 10–60 дней после регистрации.

-- 1. Начальный тариф и дата регистрации
INSERT INTO pulse.user_plan_history (user_id, valid_from, valid_to, plan)
SELECT number + 1                                                        AS user_id,
       toDateTime(today() - 120 - (number % 60))                         AS valid_from,
       if(number % 3 = 0, valid_from + INTERVAL (10 + number % 50) DAY,
                          toDateTime('2106-01-01 00:00:00'))             AS valid_to,
       ['basic', 'basic', 'pro', 'basic', 'team'][(number % 5) + 1]     AS plan
FROM numbers(1000);

-- 2. Смена тарифа для каждого третьего пользователя (открытый интервал)
INSERT INTO pulse.user_plan_history (user_id, valid_from, valid_to, plan)
SELECT user_id, valid_to AS valid_from, toDateTime('2106-01-01 00:00:00') AS valid_to,
       ['pro', 'team', 'pro'][(user_id % 3) + 1] AS plan
FROM pulse.user_plan_history
WHERE valid_to < toDateTime('2106-01-01 00:00:00');

-- 3. Профиль = последняя запись истории
INSERT INTO pulse.user_profiles (user_id, name, plan, signup_date, updated_at)
SELECT user_id,
       concat('user_', toString(user_id))   AS name,
       argMax(plan, valid_from)             AS plan,
       toDate(min(valid_from))              AS signup_date,
       max(valid_from)                      AS updated_at
FROM pulse.user_plan_history
GROUP BY user_id;

-- Проверка: интервалы истории не пересекаются и не имеют дыр
SELECT count() AS bad_intervals
FROM (
    SELECT user_id, valid_from, valid_to,
           lagInFrame(valid_to) OVER (PARTITION BY user_id ORDER BY valid_from) AS prev_to
    FROM pulse.user_plan_history
)
WHERE prev_to != toDateTime(0) AND prev_to != valid_from;

SELECT plan, count() AS users FROM pulse.user_profiles FINAL GROUP BY plan ORDER BY users DESC;
