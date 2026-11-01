using System.Security.Claims;
using System.Text;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace CourseFlow.Api.Common.Auth;

/// <summary>
/// Выпуск access-токенов (Глава 13.4). JsonWebTokenHandler — современный обработчик
/// из Microsoft.IdentityModel.JsonWebTokens; устаревший JwtSecurityTokenHandler не используем.
/// </summary>
public sealed class JwtService(IOptions<JwtOptions> options, TimeProvider timeProvider)
{
    private readonly JwtOptions _options = options.Value;

    public string GenerateAccessToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SecretKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var now = timeProvider.GetUtcNow().UtcDateTime;

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = _options.Issuer,
            Audience = _options.Audience,
            IssuedAt = now,
            NotBefore = now,
            Expires = now.AddMinutes(_options.AccessTokenMinutes),
            SigningCredentials = credentials,
            Claims = new Dictionary<string, object>
            {
                // sub — стандартный claim RFC 7519 для идентификатора субъекта
                [JwtRegisteredClaimNames.Sub] = user.Id.ToString(),
                [JwtRegisteredClaimNames.Email] = user.Email,
                [JwtRegisteredClaimNames.Jti] = Guid.NewGuid().ToString(),
                [ClaimTypes.Role] = user.Role.ToString()
            }
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }
}
