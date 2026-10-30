-- Атомарная проверка и списание квоты.
-- KEYS[1] — ключ счётчика окна
-- ARGV[1] — запрашиваемое количество
-- ARGV[2] — лимит окна
-- ARGV[3] — TTL счётчика в секундах
--
-- Возвращает {allowed, used, ttl}: allowed = 1, если списание прошло.
-- Проверка и инкремент разделены в коде приложения гонкой между GET и INCRBY;
-- здесь они выполняются одной командой на стороне Redis.

local requested = tonumber(ARGV[1])
local limit     = tonumber(ARGV[2])
local ttl       = tonumber(ARGV[3])

local current = tonumber(redis.call('GET', KEYS[1]) or '0')

if current + requested > limit then
    local remaining = redis.call('TTL', KEYS[1])
    if remaining < 0 then
        remaining = ttl
    end
    return {0, current, remaining}
end

local updated = redis.call('INCRBY', KEYS[1], requested)
if updated == requested then
    redis.call('EXPIRE', KEYS[1], ttl)
end

local remaining = redis.call('TTL', KEYS[1])
return {1, updated, remaining}
