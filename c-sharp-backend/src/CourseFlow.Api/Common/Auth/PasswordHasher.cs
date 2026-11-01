namespace CourseFlow.Api.Common.Auth;

/// <summary>Хеширование паролей (Глава 13.3). Собственная реализация без ASP.NET Core Identity.</summary>
public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string password, string hash);
}

/// <summary>
/// bcrypt: соль внутри хеша, настраиваемая стоимость (work factor),
/// намеренно медленный — перебор дампа становится нерентабельным.
/// </summary>
public sealed class BcryptPasswordHasher : IPasswordHasher
{
    private const int WorkFactor = 12; // баланс безопасности и скорости (~250 мс на хеш)

    public string Hash(string password) =>
        BCrypt.Net.BCrypt.HashPassword(password, WorkFactor);

    public bool Verify(string password, string hash) =>
        BCrypt.Net.BCrypt.Verify(password, hash);
}
