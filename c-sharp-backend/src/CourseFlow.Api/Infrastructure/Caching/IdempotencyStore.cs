using System.Text.Json;
using StackExchange.Redis;

namespace CourseFlow.Api.Infrastructure.Caching;

public enum IdempotencyStatus { Started, InProgress, Completed }

public sealed record IdempotencyState<T>(IdempotencyStatus Status, T? Result);

/// <summary>
/// Хранилище idempotency-ключей (Глава 14.5). Три состояния:
/// Started — ключ свободен и мы его заняли; InProgress — первый запрос ещё выполняется;
/// Completed — результат готов, отдаём сохранённый.
/// </summary>
public interface IIdempotencyStore
{
    Task<IdempotencyState<T>> BeginAsync<T>(string key, CancellationToken ct = default);
    Task CompleteAsync<T>(string key, T result, CancellationToken ct = default);
    Task ReleaseAsync(string key, CancellationToken ct = default);
}

public static class IdempotencyRecord
{
    public const string InProgressMarker = "__in_progress__";
}

/// <summary>
/// Реализация на Redis. Ключ занимается атомарно через SET NX (When.NotExists):
/// два параллельных повтора не пройдут оба — Redis однопоточен, второй SET вернёт false.
/// Проверка "GET, потом SET" здесь была бы гонкой.
/// </summary>
public sealed class RedisIdempotencyStore(IConnectionMultiplexer redis) : IIdempotencyStore
{
    private static readonly TimeSpan Retention = TimeSpan.FromHours(24);
    private const string Prefix = "idempotency:";

    public async Task<IdempotencyState<T>> BeginAsync<T>(string key, CancellationToken ct = default)
    {
        var db = redis.GetDatabase();
        var redisKey = Prefix + key;

        var acquired = await db.StringSetAsync(redisKey, IdempotencyRecord.InProgressMarker, Retention, When.NotExists);
        if (acquired)
            return new IdempotencyState<T>(IdempotencyStatus.Started, default);

        var existing = await db.StringGetAsync(redisKey);
        if (existing.IsNullOrEmpty || existing == IdempotencyRecord.InProgressMarker)
            return new IdempotencyState<T>(IdempotencyStatus.InProgress, default);

        return new IdempotencyState<T>(IdempotencyStatus.Completed, JsonSerializer.Deserialize<T>(existing.ToString()));
    }

    public Task CompleteAsync<T>(string key, T result, CancellationToken ct = default) =>
        redis.GetDatabase().StringSetAsync(Prefix + key, JsonSerializer.Serialize(result), Retention);

    public Task ReleaseAsync(string key, CancellationToken ct = default) =>
        redis.GetDatabase().KeyDeleteAsync(Prefix + key);
}
