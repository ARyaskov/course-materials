using System.Net;
using System.Net.Http.Json;
using CourseFlow.Api.Modules.Billing;
using CourseFlow.Api.Modules.Enrollment;
using CourseFlow.Api.Modules.Notifications;
using CourseFlow.Api.Modules.Progress;
using CourseFlow.Api.Modules.Users.Domain;
using CourseFlow.Tests.Integration.Fixtures;
using Microsoft.AspNetCore.SignalR.Client;

namespace CourseFlow.Tests.Integration.Modules.Enrollment;

/// <summary>
/// Ключевой сценарий курса (Глава 23.1): оплата → Outbox → PaymentCompleted → Enrollment →
/// EnrollmentCreated → Progress + Notification (в БД и через SignalR).
/// </summary>
[Collection("Integration")]
public class PaymentEnrollmentFlowTests(IntegrationTestFactory factory)
{
    [Fact]
    public async Task CompleteFlow_StudentPaysForCourse_GetsEnrolledWithProgressAndNotification()
    {
        // Arrange
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (student, studentId) = await factory.CreateUserClientAsync(UserRole.Student);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Flow course", lessons: 3);

        // Подписываемся на SignalR ДО действия, которое вызовет уведомление (Глава 19.7)
        var received = new TaskCompletionSource<NotificationDto>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var hub = new HubConnectionBuilder()
            .WithUrl($"{factory.Server.BaseAddress}hubs/notifications", options =>
            {
                options.HttpMessageHandlerFactory = _ => factory.Server.CreateHandler();
                options.AccessTokenProvider = () => Task.FromResult<string?>(factory.GenerateToken(studentId));
            })
            .Build();
        hub.On<NotificationDto>("notification", n => received.TrySetResult(n));
        await hub.StartAsync();

        // Act: студент оплачивает курс
        var paymentResponse = await student.PostAsJsonAsync("/api/v1/billing/payments", new { courseId = course.Id });
        paymentResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        var payment = (await paymentResponse.Content.ReadFromJsonAsync<PaymentDto>())!;
        payment.Status.Should().Be("Completed");

        // Assert: ждём, пока цепочка Outbox → bus → consumer доедет до конца.
        // Фиксированный Task.Delay сделал бы тест хрупким — опрашиваем результат с таймаутом.
        var enrollments = await TestHelpers.WaitForAsync(
            () => student.GetFromJsonAsync<List<EnrollmentDto>>("/api/v1/enrollments"),
            list => list is { Count: > 0 });
        enrollments.Should().ContainSingle(e => e.CourseId == course.Id && e.Status == "Active");

        var progress = await TestHelpers.WaitForAsync(
            async () =>
            {
                var response = await student.GetAsync($"/api/v1/progress/{course.Id}");
                return response.IsSuccessStatusCode
                    ? await response.Content.ReadFromJsonAsync<CourseProgressDto>()
                    : null;
            },
            p => p is not null);
        progress.TotalLessons.Should().Be(3);
        progress.CompletedLessons.Should().Be(0);

        var notifications = await TestHelpers.WaitForAsync(
            () => student.GetFromJsonAsync<List<NotificationDto>>("/api/v1/notifications"),
            list => list is { Count: > 0 });
        notifications.Should().Contain(n => n.Type == "EnrollmentConfirmed");

        // Real-time доставка: то же уведомление пришло по WebSocket
        var completed = await Task.WhenAny(received.Task, Task.Delay(TimeSpan.FromSeconds(15)));
        completed.Should().Be(received.Task, "notification must be pushed through SignalR");
        received.Task.Result.Type.Should().Be("EnrollmentConfirmed");

        // Записанный студент видит полный контент платного урока
        var lessons = await TestHelpers.GetLessonsAsync(student, course.Id);
        lessons.Should().OnlyContain(l => !l.IsPreview);
    }

    [Fact]
    public async Task Payment_WithSameIdempotencyKey_ReturnsSamePayment()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (student, _) = await factory.CreateUserClientAsync(UserRole.Student);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Idempotent course");
        var key = Guid.NewGuid().ToString();

        var first = await Post(student, course.Id, key);
        var second = await Post(student, course.Id, key);

        first.StatusCode.Should().Be(HttpStatusCode.Created);
        second.StatusCode.Should().Be(HttpStatusCode.Created);
        var p1 = await first.Content.ReadFromJsonAsync<PaymentDto>();
        var p2 = await second.Content.ReadFromJsonAsync<PaymentDto>();
        p2!.Id.Should().Be(p1!.Id, "the replay must return the stored result, not charge twice");

        static Task<HttpResponseMessage> Post(HttpClient client, Guid courseId, string key)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/billing/payments")
            {
                Content = JsonContent.Create(new { courseId })
            };
            request.Headers.Add("Idempotency-Key", key);
            return client.SendAsync(request);
        }
    }

    [Fact]
    public async Task Payment_DeclinedByGateway_Returns422AndDoesNotEnroll()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (student, _) = await factory.CreateUserClientAsync(UserRole.Student);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Declined course");

        var response = await student.PostAsJsonAsync("/api/v1/billing/payments",
            new { courseId = course.Id, cardToken = "fail_card" });

        response.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
        var check = await student.GetFromJsonAsync<EnrollmentCheckDto>($"/api/v1/enrollments/check/{course.Id}");
        check!.IsEnrolled.Should().BeFalse();
    }

    [Fact]
    public async Task Payment_ForAlreadyEnrolledCourse_Returns409()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (student, _) = await factory.CreateUserClientAsync(UserRole.Student);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Twice course");

        (await student.PostAsJsonAsync("/api/v1/billing/payments", new { courseId = course.Id }))
            .StatusCode.Should().Be(HttpStatusCode.Created);

        await TestHelpers.WaitForAsync(
            () => student.GetFromJsonAsync<EnrollmentCheckDto>($"/api/v1/enrollments/check/{course.Id}"),
            c => c is { IsEnrolled: true });

        var second = await student.PostAsJsonAsync("/api/v1/billing/payments", new { courseId = course.Id });
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task CompletingAllLessons_CompletesEnrollment_AndNotifies()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (student, _) = await factory.CreateUserClientAsync(UserRole.Student);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Completion course", lessons: 2);

        (await student.PostAsJsonAsync("/api/v1/billing/payments", new { courseId = course.Id }))
            .EnsureSuccessStatusCode();

        var progress = await TestHelpers.WaitForAsync(
            async () =>
            {
                var response = await student.GetAsync($"/api/v1/progress/{course.Id}");
                return response.IsSuccessStatusCode
                    ? await response.Content.ReadFromJsonAsync<CourseProgressDto>()
                    : null;
            },
            p => p is not null);

        foreach (var lesson in progress.LessonProgresses)
        {
            var response = await student.PostAsync($"/api/v1/progress/lessons/{lesson.LessonId}/complete", null);
            response.StatusCode.Should().Be(HttpStatusCode.NoContent);
        }

        var enrollments = await TestHelpers.WaitForAsync(
            () => student.GetFromJsonAsync<List<EnrollmentDto>>("/api/v1/enrollments"),
            list => list != null && list.Any(e => e.CourseId == course.Id && e.Status == "Completed"));
        enrollments.Should().ContainSingle(e => e.CourseId == course.Id).Which.CompletedAt.Should().NotBeNull();

        var notifications = await TestHelpers.WaitForAsync(
            () => student.GetFromJsonAsync<List<NotificationDto>>("/api/v1/notifications"),
            list => list != null && list.Any(n => n.Type == "CourseCompleted"));
        notifications.Should().Contain(n => n.Type == "CourseCompleted");
    }
}
