using System.Net;
using System.Net.Http.Json;
using CourseFlow.Api.Modules.Courses;
using CourseFlow.Api.Modules.Users.Domain;
using CourseFlow.Tests.Integration.Fixtures;

namespace CourseFlow.Tests.Integration.Modules.Courses;

[Collection("Integration")]
public class CoursesIntegrationTests(IntegrationTestFactory factory)
{
    [Fact]
    public async Task CreateCourse_AsInstructor_Returns201()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);

        var response = await instructor.PostAsJsonAsync("/api/v1/courses", new
        {
            title = "C# Backend Development",
            description = "A comprehensive course",
            price = 49.99m
        });

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
        var body = await response.Content.ReadFromJsonAsync<CourseDto>();
        body!.Title.Should().Be("C# Backend Development");
        body.Status.Should().Be("Draft");
    }

    [Fact]
    public async Task CreateCourse_AsStudent_Returns403()
    {
        var (student, _) = await factory.CreateUserClientAsync(UserRole.Student);

        var response = await student.PostAsJsonAsync("/api/v1/courses",
            new { title = "Unauthorized Course", description = "x", price = 1 });

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task CreateCourse_InvalidBody_Returns422()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);

        var response = await instructor.PostAsJsonAsync("/api/v1/courses",
            new { title = "", description = "x", price = -5 });

        response.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
    }

    [Fact]
    public async Task GetPublishedCourses_Anonymous_Returns200WithSeededCourse()
    {
        var anon = factory.CreateClient();

        var response = await anon.GetAsync("/api/v1/courses?page=1&pageSize=10");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var page = await response.Content.ReadFromJsonAsync<PagedResult<CourseDto>>();
        page!.Items.Should().NotBeEmpty();
        page.Items.Should().OnlyContain(c => c.Status == "Published");
    }

    [Fact]
    public async Task GetDraftCourse_ByStranger_Returns404_ByAuthor_Returns200()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var create = await instructor.PostAsJsonAsync("/api/v1/courses",
            new { title = "Draft", description = "hidden", price = 10 });
        var course = (await create.Content.ReadFromJsonAsync<CourseDto>())!;

        var anon = factory.CreateClient();
        (await anon.GetAsync($"/api/v1/courses/{course.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await instructor.GetAsync($"/api/v1/courses/{course.Id}")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Publish_WithoutLessons_Returns409WithErrorCode()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var create = await instructor.PostAsJsonAsync("/api/v1/courses",
            new { title = "Empty", description = "no lessons", price = 10 });
        var course = (await create.Content.ReadFromJsonAsync<CourseDto>())!;

        var response = await instructor.PostAsync($"/api/v1/courses/{course.Id}/publish", null);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var problem = await response.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        problem!["code"].ToString().Should().Be("Course.NoLessons");
    }

    [Fact]
    public async Task Update_ForeignCourse_Returns403()
    {
        var (owner, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var (other, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var create = await owner.PostAsJsonAsync("/api/v1/courses",
            new { title = "Mine", description = "x", price = 10 });
        var course = (await create.Content.ReadFromJsonAsync<CourseDto>())!;

        var response = await other.PutAsJsonAsync($"/api/v1/courses/{course.Id}",
            new { title = "Hijacked", description = "x", price = 10 });

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task GetPublishedCourse_IsServedFromCache_AfterFirstRead()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Cached course");
        var anon = factory.CreateClient();

        var first = await anon.GetFromJsonAsync<CourseDto>($"/api/v1/courses/{course.Id}");
        var second = await anon.GetFromJsonAsync<CourseDto>($"/api/v1/courses/{course.Id}");

        first.Should().BeEquivalentTo(second);
        second!.Status.Should().Be("Published");
    }

    [Fact]
    public async Task Lessons_PaidLesson_IsPreviewForAnonymous_AndFullForAuthor()
    {
        var (instructor, _) = await factory.CreateUserClientAsync(UserRole.Instructor);
        var course = await TestHelpers.CreateAndPublishCourseAsync(instructor, "Lessons access", lessons: 1);
        var anon = factory.CreateClient();

        var anonLessons = await TestHelpers.GetLessonsAsync(anon, course.Id);
        var authorLessons = await TestHelpers.GetLessonsAsync(instructor, course.Id);

        anonLessons.Should().ContainSingle().Which.IsPreview.Should().BeTrue();
        anonLessons[0].TextContent.Should().BeNull();
        authorLessons.Should().ContainSingle().Which.TextContent.Should().Be("Content 1");
    }

    [Fact]
    public async Task GraphQL_PublishedCourses_ReturnsData()
    {
        var anon = factory.CreateClient();

        var response = await anon.PostAsJsonAsync("/graphql", new
        {
            query = "{ publishedCourses(order: [{ publishedAt: DESC }]) { id title price status } }"
        });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("\"publishedCourses\"").And.NotContain("\"errors\"");
    }
}
