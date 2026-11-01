using System.Net.Http.Json;
using CourseFlow.Api.Modules.Courses;
using CourseFlow.Api.Modules.Lessons;

namespace CourseFlow.Tests.Integration.Fixtures;

public static class TestHelpers
{
    /// <summary>
    /// Опрашивает источник, пока результат не удовлетворит условию либо не истечёт таймаут.
    /// Замена Task.Delay в тестах асинхронных цепочек (Outbox → bus → consumer).
    /// </summary>
    public static async Task<T> WaitForAsync<T>(
        Func<Task<T?>> probe,
        Func<T?, bool> predicate,
        TimeSpan? timeout = null,
        TimeSpan? interval = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(20));
        var delay = interval ?? TimeSpan.FromMilliseconds(200);

        while (DateTime.UtcNow < deadline)
        {
            var value = await probe();
            if (predicate(value))
                return value!;

            await Task.Delay(delay);
        }

        throw new TimeoutException($"Expected state was not reached within {(timeout ?? TimeSpan.FromSeconds(20)).TotalSeconds:0}s");
    }

    /// <summary>Создаёт курс с одним уроком и публикует его от имени инструктора.</summary>
    public static async Task<CourseDto> CreateAndPublishCourseAsync(
        HttpClient instructorClient, string title = "Integration Course", decimal price = 49.99m, int lessons = 1)
    {
        var createResponse = await instructorClient.PostAsJsonAsync("/api/v1/courses",
            new { title, description = "Created by integration tests", price });
        createResponse.EnsureSuccessStatusCode();
        var course = (await createResponse.Content.ReadFromJsonAsync<CourseDto>())!;

        for (var i = 1; i <= lessons; i++)
        {
            var lessonResponse = await instructorClient.PostAsJsonAsync(
                $"/api/v1/courses/{course.Id}/lessons",
                new { title = $"Lesson {i}", type = "Text", textContent = $"Content {i}" });
            lessonResponse.EnsureSuccessStatusCode();
        }

        var publishResponse = await instructorClient.PostAsync($"/api/v1/courses/{course.Id}/publish", null);
        publishResponse.EnsureSuccessStatusCode();

        return (await publishResponse.Content.ReadFromJsonAsync<CourseDto>())!;
    }

    public static async Task<IReadOnlyList<LessonDto>> GetLessonsAsync(HttpClient client, Guid courseId) =>
        (await client.GetFromJsonAsync<List<LessonDto>>($"/api/v1/courses/{courseId}/lessons"))!;
}
