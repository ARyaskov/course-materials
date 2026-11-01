-- Pulse: спаны для части запросов из app_logs (глава 15). Три спана на трассу: gateway -> orders -> db.
-- request_id совпадает с логами, чтобы расследование по идентификатору проходило через обе таблицы.
INSERT INTO pulse.spans (trace_id, span_id, parent_span_id, request_id, service, operation, start_ts, duration_us, status, attributes)
SELECT
    trace_id,
    span_id,
    parent_span_id,
    request_id,
    service,
    operation,
    start_ts,
    duration_us,
    if(has_error AND depth = 1, 'ERROR', 'OK') AS status,
    map('endpoint', endpoint, 'depth', toString(depth)) AS attributes
FROM (
    SELECT
        l.request_id,
        l.endpoint,
        l.ts AS log_ts,
        l.has_error,
        depth,
        toUUID(concat(substring(h, 1, 8), '-', substring(h, 9, 4), '-', substring(h, 13, 4), '-', substring(h, 17, 4), '-', substring(h, 21, 12))) AS trace_id,
        cityHash64(l.request_id, depth) AS span_id,
        if(depth = 0, 0, cityHash64(l.request_id, depth - 1)) AS parent_span_id,
        ['gateway', 'orders', 'db'][depth + 1] AS service,
        ['http.request', 'process.order', 'sql.query'][depth + 1] AS operation,
        toDateTime64(log_ts, 6) + toIntervalMillisecond(depth * 5) AS start_ts,
        toUInt64(if(has_error, 4000, 60) * 1000 / (depth + 1) + rand(1) % 20000) AS duration_us
    FROM (
        SELECT request_id, any(endpoint) AS endpoint, min(ts) AS ts, max(level = 'ERROR') AS has_error,
               lower(concat(hex(cityHash64(request_id)), hex(sipHash64(request_id)))) AS h
        FROM pulse.app_logs
        WHERE ts >= now() - INTERVAL 3 DAY
        GROUP BY request_id
        HAVING cityHash64(request_id) % 5 = 0        -- каждая пятая трасса
    ) AS l
    ARRAY JOIN [0, 1, 2] AS depth
);

SELECT service, count() AS spans, quantileTDigest(0.95)(duration_us) / 1000 AS p95_ms FROM pulse.spans GROUP BY service;
