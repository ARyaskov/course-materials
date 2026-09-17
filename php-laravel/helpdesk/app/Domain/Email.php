<?php
// app/Domain/Email.php
declare(strict_types=1);

namespace App\Domain;

use InvalidArgumentException;
use Stringable;

final readonly class Email implements Stringable, \JsonSerializable
{
    public string $value;

    public function __construct(string $value)
    {
        $normalized = mb_strtolower(trim($value));

        if (filter_var($normalized, FILTER_VALIDATE_EMAIL) === false) {
            throw new InvalidArgumentException("Некорректный адрес: {$value}");
        }

        $this->value = $normalized;
    }

    public function domain(): string
    {
        return substr($this->value, strpos($this->value, '@') + 1);
    }

    public function isCorporate(array $corporateDomains): bool
    {
        return in_array($this->domain(), $corporateDomains, strict: true);
    }

    public function masked(): string
    {
        [$user, $domain] = explode('@', $this->value);

        return mb_substr($user, 0, 2) . str_repeat('*', max(mb_strlen($user) - 2, 1)) . '@' . $domain;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }

    public function jsonSerialize(): string
    {
        return $this->value;
    }
}

$email = new Email('  IRINA@Example.COM ');

echo $email->value;      // irina@example.com — нормализовано
echo $email->domain();   // example.com
echo $email->masked();   // ir****@example.com
echo json_encode(['email' => $email]);   // {"email":"irina@example.com"}
