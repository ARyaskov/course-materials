using CourseFlow.Api.Modules.Enrollment.Domain;
using CourseFlow.Api.Modules.Lessons.Domain;
using CourseFlow.Api.Modules.Progress.Domain;

namespace CourseFlow.Tests.Unit.Domain;

public class LessonTests
{
    [Fact]
    public void UpdateContent_VideoWithoutUrl_ThrowsInvalidOperation()
    {
        var lesson = Lesson.Create(Guid.NewGuid(), "Intro", LessonType.Video, 1);

        var act = () => lesson.UpdateContent("desc", contentUrl: null, textContent: null, duration: null);

        act.Should().Throw<InvalidOperationException>().WithMessage("*ContentUrl*");
    }

    [Fact]
    public void Create_WithNonPositiveOrder_ThrowsArgumentException()
    {
        var act = () => Lesson.Create(Guid.NewGuid(), "Intro", LessonType.Text, 0);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void MakeFree_ThenMakePaid_TogglesFlag()
    {
        var lesson = Lesson.Create(Guid.NewGuid(), "Intro", LessonType.Text, 1);

        lesson.MakeFree();
        lesson.IsFree.Should().BeTrue();

        lesson.MakePaid();
        lesson.IsFree.Should().BeFalse();
    }
}

public class EnrollmentTests
{
    [Fact]
    public void Complete_ActiveEnrollment_SetsCompletedAt()
    {
        var enrollment = Enrollment.Create(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());

        enrollment.Complete();

        enrollment.Status.Should().Be(EnrollmentStatus.Completed);
        enrollment.CompletedAt.Should().NotBeNull();
    }

    [Fact]
    public void Complete_Twice_IsIdempotent()
    {
        var enrollment = Enrollment.Create(Guid.NewGuid(), Guid.NewGuid());
        enrollment.Complete();
        var firstCompletedAt = enrollment.CompletedAt;

        enrollment.Complete();

        enrollment.CompletedAt.Should().Be(firstCompletedAt);
    }

    [Fact]
    public void Complete_RevokedEnrollment_ThrowsInvalidOperation()
    {
        var enrollment = Enrollment.Create(Guid.NewGuid(), Guid.NewGuid());
        enrollment.Revoke();

        var act = () => enrollment.Complete();

        act.Should().Throw<InvalidOperationException>();
    }
}

public class LessonProgressTests
{
    [Fact]
    public void MarkCompleted_IsIdempotent()
    {
        var progress = LessonProgress.Create(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());

        progress.MarkCompleted();
        var completedAt = progress.CompletedAt;
        progress.MarkCompleted();

        progress.Status.Should().Be(ProgressStatus.Completed);
        progress.CompletedAt.Should().Be(completedAt);
    }

    [Fact]
    public void UpdateVideoProgress_MovesNotStartedToInProgress()
    {
        var progress = LessonProgress.Create(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());

        progress.UpdateVideoProgress(42);

        progress.Status.Should().Be(ProgressStatus.InProgress);
        progress.LastWatchedSeconds.Should().Be(42);
    }

    [Fact]
    public void UpdateVideoProgress_DoesNotDowngradeCompleted()
    {
        var progress = LessonProgress.Create(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        progress.MarkCompleted();

        progress.UpdateVideoProgress(10);

        progress.Status.Should().Be(ProgressStatus.Completed);
    }
}
