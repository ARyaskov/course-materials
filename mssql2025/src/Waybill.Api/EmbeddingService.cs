// Эмбеддинги на стороне приложения (глава 14): Ollama /api/embed по HTTP; при Ai:Enabled=false — null, и сервер использует свой путь.
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Waybill.Api;

public sealed class AiOptions
{
    public bool Enabled { get; set; } = false;
    public string EmbeddingsUrl { get; set; } = "http://localhost:11434/api/embed";
    public string Model { get; set; } = "nomic-embed-text";
    public int Dimensions { get; set; } = 768;
    public int TimeoutSeconds { get; set; } = 15;
}

public sealed class EmbeddingService(IHttpClientFactory httpFactory, IOptions<AiOptions> options, ILogger<EmbeddingService> logger)
{
    public bool Enabled => options.Value.Enabled;
    public string Model => options.Value.Model;

    /// <summary>Вектор текста или null (AI выключен либо модель недоступна) — вызывающий переходит на серверный путь.</summary>
    public async Task<float[]?> EmbedAsync(string text, CancellationToken ct)
    {
        var o = options.Value;
        if (!o.Enabled) return null;
        try
        {
            var client = httpFactory.CreateClient("ollama");
            client.Timeout = TimeSpan.FromSeconds(o.TimeoutSeconds);
            using var response = await client.PostAsJsonAsync(o.EmbeddingsUrl, new { model = o.Model, input = text }, ct);
            response.EnsureSuccessStatusCode();
            using var doc = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
            var arr = doc.RootElement.GetProperty("embeddings")[0];                         // Ollama: { "embeddings": [[...]] }
            var v = new float[arr.GetArrayLength()];
            var i = 0;
            foreach (var x in arr.EnumerateArray()) v[i++] = x.GetSingle();
            if (v.Length != o.Dimensions) { logger.LogWarning("embedding dimensions {Got} != {Expected}", v.Length, o.Dimensions); return null; }
            return v;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "embedding model unavailable, falling back to server-side embedding");
            return null;
        }
    }
}
