using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using NSubstitute;

namespace CourseFlow.Tests.Unit.Auth;

public class BcryptPasswordHasherTests
{
    private readonly BcryptPasswordHasher _hasher = new();

    [Fact]
    public void Hash_ThenVerify_SucceedsForCorrectPassword()
    {
        var hash = _hasher.Hash("S3cret!pass");

        _hasher.Verify("S3cret!pass", hash).Should().BeTrue();
    }

    [Fact]
    public void Verify_FailsForWrongPassword()
    {
        var hash = _hasher.Hash("S3cret!pass");

        _hasher.Verify("wrong", hash).Should().BeFalse();
    }

    [Fact]
    public void Hash_IsSalted_SamePasswordProducesDifferentHashes()
    {
        _hasher.Hash("same").Should().NotBe(_hasher.Hash("same"));
    }
}

public class RefreshTokenTests
{
    [Fact]
    public void IssueRefreshToken_StoresOnlyHash()
    {
        var user = User.Create("a@b.io", "hash", "A", "B");

        var (value, entity) = user.IssueRefreshToken(TimeSpan.FromDays(1));

        entity.TokenHash.Should().NotBe(value);
        entity.TokenHash.Should().Be(RefreshToken.Hash(value));
        entity.IsActive.Should().BeTrue();
        user.RefreshTokens.Should().ContainSingle();
    }

    [Fact]
    public void RevokeAllRefreshTokens_DeactivatesEveryToken()
    {
        var user = User.Create("a@b.io", "hash", "A", "B");
        user.IssueRefreshToken(TimeSpan.FromDays(1));
        user.IssueRefreshToken(TimeSpan.FromDays(1));

        user.RevokeAllRefreshTokens();

        user.RefreshTokens.Should().OnlyContain(t => t.IsRevoked);
    }

    [Fact]
    public void Hash_IsDeterministic()
    {
        RefreshToken.Hash("token").Should().Be(RefreshToken.Hash("token"));
    }
}

public class JwtServiceTests
{
    private static readonly JwtOptions Options = new()
    {
        SecretKey = "unit-test-secret-key-at-least-32-characters-long",
        Issuer = "courseflow-api",
        Audience = "courseflow-clients",
        AccessTokenMinutes = 15
    };

    [Fact]
    public void GenerateAccessToken_ContainsSubEmailAndRoleClaims()
    {
        // TimeProvider подменяем через NSubstitute: время выпуска токена детерминировано
        var clock = Substitute.For<TimeProvider>();
        clock.GetUtcNow().Returns(new DateTimeOffset(2026, 1, 1, 12, 0, 0, TimeSpan.Zero));

        var user = User.Create("student@test.io", "hash", "Sam", "Student");
        user.SetRole(UserRole.Instructor);
        var sut = new JwtService(Microsoft.Extensions.Options.Options.Create(Options), clock);

        var token = sut.GenerateAccessToken(user);

        var jwt = new JsonWebTokenHandler().ReadJsonWebToken(token);
        jwt.Subject.Should().Be(user.Id.ToString());
        jwt.GetClaim(JwtRegisteredClaimNames.Email).Value.Should().Be("student@test.io");
        jwt.GetClaim(System.Security.Claims.ClaimTypes.Role).Value.Should().Be("Instructor");
        jwt.Issuer.Should().Be(Options.Issuer);
        jwt.ValidTo.Should().Be(new DateTime(2026, 1, 1, 12, 15, 0, DateTimeKind.Utc));
    }
}

public class CurrentUserExtensionsTests
{
    [Fact]
    public void RequiredUserId_ForAnonymous_Throws()
    {
        var currentUser = Substitute.For<ICurrentUser>();
        currentUser.UserId.Returns((Guid?)null);

        var act = () => currentUser.RequiredUserId();

        act.Should().Throw<InvalidOperationException>().WithMessage("*not authenticated*");
    }

    [Fact]
    public void RequiredUserId_ForAuthenticated_ReturnsId()
    {
        var id = Guid.NewGuid();
        var currentUser = Substitute.For<ICurrentUser>();
        currentUser.UserId.Returns(id);

        currentUser.RequiredUserId().Should().Be(id);
    }
}
