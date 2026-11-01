-- Нагрузочные данные для профилирования (урок 14.6): 50 000 броней по комнатам из V900 seed на 200 дней вперёд.
INSERT INTO bookings (id, room_id, member_id, slot, status, created_at, version)
SELECT gen_random_uuid(),
       r.id,
       gen_random_uuid(),
       tstzrange(day_start + (g % 40) * interval '20 minutes', day_start + (g % 40) * interval '20 minutes' + interval '15 minutes', '[)'),
       'CONFIRMED',
       now(),
       0
FROM generate_series(1, 50000) AS g
CROSS JOIN LATERAL (SELECT id FROM rooms ORDER BY id OFFSET (g % (SELECT count(*) FROM rooms)) LIMIT 1) AS r
CROSS JOIN LATERAL (SELECT date_trunc('day', now()) + (g / 40) * interval '1 day' + interval '8 hours' AS day_start) AS d
ON CONFLICT DO NOTHING;
