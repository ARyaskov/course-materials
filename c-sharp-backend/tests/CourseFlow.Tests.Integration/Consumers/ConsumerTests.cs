using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Enrollment.Consumers;
using CourseFlow.Api.Modules.Lessons.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using CourseFlow.Contracts;
using CourseFlow.Tests.Integration.Fixtures;
using MassTransit;
using MassTransit.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CourseFlow.Tests.Integration.Consumers;

/// <summary>
/// Тесты consumer-ов через MassTransit test harness (Глава 19.8, 23.10): реальная БД,
/// in-memory транспорт, без RabbitMQ. Изолированный ServiceProvider — чтобы проверить
/// ровно один consumer, а не всю цепочку приложения.
/// </summary>
[Collection("Integration")]
public class PaymentCompletedConsumerTests(IntegrationTestFactory factory)
{
    [Fact]
    public async Task Consume_NewPayment_CreatesEnrollmentAndPublishesEvent()
    {
        await using var provider = new ServiceCollection()
            .AddLogging()
            .AddDbContext<AppDbContext>(o => o
                .UseNpgsql(factory.PostgresConnectionString)
                .UseSnakeCaseNamingConvention())
            .AddMassTransitTestHarness(cfg => cfg.AddConsumer<PaymentCompletedConsumer>())
            .BuildServiceProvider(true);

        var harness = provider.GetRequiredService<ITestHarness>();
        await harness.Start();

        // Consumer проверяет, что курс существует и опубликован, — готовим опубликованный курс
        Guid courseId;
        Guid userId;
        using (var scope = provider.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            var author = User.Create($"{Guid.NewGuid():N}@test.local", "hash", "A", "B");
            var student = User.Create($"{Guid.NewGuid():N}@test.local", "hash", "S", "T");
            db.Users.AddRange(author, student);

            var course = Course.Create("Consumer test course", "Описание", author.Id, 49.99m);
            course.AddLesson("Lesson 1", LessonType.Text);
            course.Publish();
            db.Courses.Add(course);

            await db.SaveChangesAsync();
            courseId = course.Id;
            userId = student.Id;
        }

        var paymentId = Guid.NewGuid();
        await harness.Bus.Publish(new PaymentCompleted(
            PaymentId: paymentId,
            CourseId: courseId,
            UserId: userId,
            Amount: 49.99m,
            PaidAt: DateTimeOffset.UtcNow));

        // Consumer обработал
        var consumerHarness = harness.GetConsumerHarness<PaymentCompletedConsumer>();
        (await consumerHarness.Consumed.Any<PaymentCompleted>()).Should().BeTrue();

        // Enrollment создан в БД. Читаем через отдельный scope:
        // consumer работал в своём, и его изменения в нашем DbContext не видны
        using var verifyScope = provider.CreateScope();
        var verifyDb = verifyScope.ServiceProvider.GetRequiredService<AppDbContext>();
        var enrollment = await verifyDb.Enrollments.FirstOrDefaultAsync(
            e => e.UserId == userId && e.CourseId == courseId);
        enrollment.Should().NotBeNull();
        enrollment!.PaymentId.Should().Be(paymentId);

        // EnrollmentCreated опубликован
        (await harness.Published.Any<EnrollmentCreated>()).Should().BeTrue();
    }

    [Fact]
    public async Task Consume_DuplicatePayment_DoesNotCreateSecondEnrollment()
    {
        await using var provider = new ServiceCollection()
            .AddLogging()
            .AddDbContext<AppDbContext>(o => o
                .UseNpgsql(factory.PostgresConnectionString)
                .UseSnakeCaseNamingConvention())
            .AddMassTransitTestHarness(cfg => cfg.AddConsumer<PaymentCompletedConsumer>())
            .BuildServiceProvider(true);

        var harness = provider.GetRequiredService<ITestHarness>();
        await harness.Start();

        Guid courseId, userId;
        using (var scope = provider.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var author = User.Create($"{Guid.NewGuid():N}@test.local", "hash", "A", "B");
            var student = User.Create($"{Guid.NewGuid():N}@test.local", "hash", "S", "T");
            db.Users.AddRange(author, student);
            var course = Course.Create("Dup course", "d", author.Id, 10m);
            course.AddLesson("L", LessonType.Text);
            course.Publish();
            db.Courses.Add(course);
            await db.SaveChangesAsync();
            courseId = course.Id;
            userId = student.Id;
        }

        var message = new PaymentCompleted(Guid.NewGuid(), courseId, userId, 10m, DateTimeOffset.UtcNow);
        await harness.Bus.Publish(message);
        await harness.Bus.Publish(message); // повторная доставка того же события

        var consumerHarness = harness.GetConsumerHarness<PaymentCompletedConsumer>();
        await TestHelpers.WaitForAsync(
            async () => await consumerHarness.Consumed.SelectAsync<PaymentCompleted>().Count(),
            count => count >= 2);

        using var verifyScope = provider.CreateScope();
        var verifyDb = verifyScope.ServiceProvider.GetRequiredService<AppDbContext>();
        (await verifyDb.Enrollments.CountAsync(e => e.UserId == userId && e.CourseId == courseId)).Should().Be(1);
    }
}
