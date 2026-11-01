using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Lessons.Domain;

namespace CourseFlow.Tests.Unit.Domain;

public class CourseTests
{
    [Fact]
    public void Publish_WithLessons_ChangesStatusToPublished()
    {
        var course = Course.Create("Test", "Desc", Guid.NewGuid(), 49.99m);

        // Урок нужно именно ДОБАВИТЬ в курс: просто создать объект недостаточно,
        // Publish() проверяет непустую коллекцию Lessons
        course.AddLesson("Lesson 1", LessonType.Text);

        course.Publish();

        course.Status.Should().Be(CourseStatus.Published);
        course.PublishedAt.Should().NotBeNull();
        course.PublishedAt!.Value.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromSeconds(5));
    }

    [Fact]
    public void Publish_WithoutLessons_ThrowsInvalidOperation()
    {
        var course = Course.Create("Test", "Desc", Guid.NewGuid(), 49.99m);

        var act = () => course.Publish();

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*without lessons*");
    }

    [Fact]
    public void Publish_Twice_ThrowsInvalidOperation()
    {
        var course = CreatePublishedCourse();

        var act = () => course.Publish();

        act.Should().Throw<InvalidOperationException>().WithMessage("*already published*");
    }

    [Fact]
    public void Update_PublishedCourse_ThrowsInvalidOperation()
    {
        var course = CreatePublishedCourse();

        var act = () => course.Update("New Title", "New Desc", 99m);

        act.Should().Throw<InvalidOperationException>();
    }

    [Theory]
    [InlineData(-0.01)]
    [InlineData(-100)]
    public void Create_WithNegativePrice_ThrowsArgumentException(decimal price)
    {
        var act = () => Course.Create("Test", "Desc", Guid.NewGuid(), price);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void AddLesson_AssignsSequentialOrderIndex()
    {
        var course = Course.Create("Test", "Desc", Guid.NewGuid(), 10m);

        var first = course.AddLesson("One", LessonType.Text);
        var second = course.AddLesson("Two", LessonType.Video);

        first.OrderIndex.Should().Be(1);
        second.OrderIndex.Should().Be(2);
        course.Lessons.Should().HaveCount(2);
    }

    [Fact]
    public void AddLesson_ToArchivedCourse_ThrowsInvalidOperation()
    {
        var course = Course.Create("Test", "Desc", Guid.NewGuid(), 10m);
        course.Archive();

        var act = () => course.AddLesson("One", LessonType.Text);

        act.Should().Throw<InvalidOperationException>().WithMessage("*archived*");
    }

    private static Course CreatePublishedCourse()
    {
        var course = Course.Create("Test", "Desc", Guid.NewGuid(), 49.99m);
        course.AddLesson("Lesson 1", LessonType.Text);
        course.Publish();
        return course;
    }
}
