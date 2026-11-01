using CourseFlow.Api.Common.Errors;
using Microsoft.AspNetCore.Http.HttpResults;

namespace CourseFlow.Tests.Unit.Common;

public class ResultTests
{
    [Fact]
    public void Error_ImplicitlyConvertsToFailedResult()
    {
        Result<int> result = Error.NotFound("nope");

        result.IsFailure.Should().BeTrue();
        result.Error.Type.Should().Be(ErrorType.NotFound);
    }

    [Fact]
    public void Value_OfFailedResult_Throws()
    {
        Result<int> result = Error.Conflict("dup");

        var act = () => result.Value;

        act.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void Success_CarriesValue()
    {
        var result = Result.Success(42);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().Be(42);
        result.Error.Should().Be(Error.None);
    }

    [Theory]
    [InlineData(ErrorType.NotFound, 404)]
    [InlineData(ErrorType.Conflict, 409)]
    [InlineData(ErrorType.Forbidden, 403)]
    [InlineData(ErrorType.Unauthorized, 401)]
    [InlineData(ErrorType.Validation, 422)]
    [InlineData(ErrorType.TooManyRequests, 429)]
    [InlineData(ErrorType.ExternalService, 502)]
    [InlineData(ErrorType.Failure, 500)]
    public void ToHttpResult_MapsErrorTypeToStatusCode(ErrorType type, int expectedStatus)
    {
        var error = new Error("Test.Code", "description", type);

        var httpResult = error.ToHttpResult();

        httpResult.Should().BeOfType<ProblemHttpResult>()
            .Which.StatusCode.Should().Be(expectedStatus);
    }

    [Fact]
    public void ToHttpResult_HidesDetailsForInternalErrors()
    {
        var error = new Error("Test.Code", "sensitive details", ErrorType.Failure);

        var problem = (ProblemHttpResult)error.ToHttpResult();

        problem.ProblemDetails.Detail.Should().BeNull();
    }
}
