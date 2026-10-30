-- Возврат ранее списанной квоты: событие не прошло валидацию после проверки лимита.
-- KEYS[1] — ключ счётчика, ARGV[1] — количество к возврату.
-- DECRBY может увести счётчик ниже нуля, если ключ успел истечь, поэтому нижняя граница — 0.

local amount = tonumber(ARGV[1])
local current = tonumber(redis.call('GET', KEYS[1]) or '0')

if current <= amount then
    redis.call('SET', KEYS[1], 0, 'KEEPTTL')
    return 0
end

return redis.call('DECRBY', KEYS[1], amount)
