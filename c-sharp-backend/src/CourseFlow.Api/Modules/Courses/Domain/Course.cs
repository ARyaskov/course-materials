using CourseFlow.Api.Modules.Lessons.Domain;

namespace CourseFlow.Api.Modules.Courses.Domain;

public enum CourseStatus { Draft, Published, Archived }

/// <summary>Курс (Глава 23.3). Бизнес-правила публикации живут здесь, а не в сервисе.</summary>
public class Course
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public string Title { get; private set; } = null!;
    public string Description { get; private set; } = null!;
    public Guid AuthorId { get; private set; }
    public decimal Price { get; private set; }
    public CourseStatus Status { get; private set; } = CourseStatus.Draft;
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? PublishedAt { get; private set; }
    public string? ThumbnailUrl { get; private set; }

    private readonly List<Lesson> _lessons = [];
    public IReadOnlyList<Lesson> Lessons => _lessons;

    private Course() { } // EF Core

    public static Course Create(string title, string description, Guid authorId, decimal price)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        if (price < 0) throw new ArgumentException("Price cannot be negative", nameof(price));

        return new Course
        {
            Title = title.Trim(),
            Description = description?.Trim() ?? string.Empty,
            AuthorId = authorId,
            Price = price
        };
    }

    public void Update(string title, string description, decimal price)
    {
        if (Status == CourseStatus.Published)
            throw new InvalidOperationException(
                "Cannot update published course directly. Create a new version.");

        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        if (price < 0) throw new ArgumentException("Price cannot be negative", nameof(price));

        Title = title.Trim();
        Description = description?.Trim() ?? string.Empty;
        Price = price;
    }

    public void SetThumbnail(string? url) => ThumbnailUrl = url;

    public bool CanBePublished => Status == CourseStatus.Draft && _lessons.Count > 0;

    public void Publish()
    {
        if (Status == CourseStatus.Published)
            throw new InvalidOperationException("Course is already published");

        if (_lessons.Count == 0)
            throw new InvalidOperationException("Cannot publish course without lessons");

        Status = CourseStatus.Published;
        PublishedAt = DateTimeOffset.UtcNow;
    }

    public void Archive() => Status = CourseStatus.Archived;

    /// <summary>Добавляет урок через агрегат: порядковый номер вычисляется как max(order) + 1.</summary>
    public Lesson AddLesson(string title, LessonType type)
    {
        if (Status == CourseStatus.Archived)
            throw new InvalidOperationException("Cannot add lessons to archived course");

        var nextOrderIndex = _lessons.Count != 0 ? _lessons.Max(l => l.OrderIndex) + 1 : 1;
        var lesson = Lesson.Create(Id, title, type, nextOrderIndex);
        _lessons.Add(lesson);
        return lesson;
    }

    public void RemoveLesson(Lesson lesson) => _lessons.Remove(lesson);
}
