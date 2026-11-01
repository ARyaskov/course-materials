namespace CourseFlow.Api.Modules.Lessons.Domain;

public enum LessonType { Video, Text, Quiz, Assignment }

/// <summary>Урок курса (Глава 23.4).</summary>
public class Lesson
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid CourseId { get; private set; }
    public string Title { get; private set; } = null!;
    public string? Description { get; private set; }
    public LessonType Type { get; private set; }
    public string? ContentUrl { get; private set; }   // URL видео или документа
    public string? TextContent { get; private set; }  // для текстовых уроков
    public int OrderIndex { get; private set; }
    public TimeSpan? Duration { get; private set; }
    public bool IsFree { get; private set; }          // превью-урок
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;

    private Lesson() { } // EF Core

    public static Lesson Create(Guid courseId, string title, LessonType type, int order)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        if (order < 1) throw new ArgumentException("Order must be positive", nameof(order));

        return new Lesson
        {
            CourseId = courseId,
            Title = title.Trim(),
            Type = type,
            OrderIndex = order
        };
    }

    public void UpdateContent(string? description, string? contentUrl, string? textContent, TimeSpan? duration)
    {
        if (Type == LessonType.Video && string.IsNullOrEmpty(contentUrl))
            throw new InvalidOperationException("Video lesson requires ContentUrl");

        Description = description;
        ContentUrl = contentUrl;
        TextContent = textContent;
        Duration = duration;
    }

    public void Rename(string title)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        Title = title.Trim();
    }

    public void MakeFree() => IsFree = true;
    public void MakePaid() => IsFree = false;

    public void Reorder(int newOrder)
    {
        if (newOrder < 1) throw new ArgumentException("Order must be positive", nameof(newOrder));
        OrderIndex = newOrder;
    }
}
