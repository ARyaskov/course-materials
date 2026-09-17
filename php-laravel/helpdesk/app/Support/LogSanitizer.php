<?php
// app/Support/LogSanitizer.php
declare(strict_types=1);

namespace App\Support;

final readonly class LogSanitizer
{
    private const array HIDDEN = [
        'password', 'password_confirmation', 'current_password',
        'token', 'access_token', 'secret', 'api_key', 'authorization',
    ];

    private const array MASKED = ['email', 'phone'];

    /** @param  array<string, mixed>  $data */
    public static function clean(array $data): array
    {
        $result = [];

        foreach ($data as $key => $value) {
            $lower = mb_strtolower((string) $key);

            $result[$key] = match (true) {
                in_array($lower, self::HIDDEN, strict: true) => '[скрыто]',
                in_array($lower, self::MASKED, strict: true) => self::mask((string) $value),
                is_array($value)                             => self::clean($value),
                default                                      => $value,
            };
        }

        return $result;
    }

    private static function mask(string $value): string
    {
        if (str_contains($value, '@')) {
            [$user, $domain] = explode('@', $value, 2);

            return mb_substr($user, 0, 2) . str_repeat('*', 3) . '@' . $domain;
        }

        return mb_substr($value, 0, 3) . str_repeat('*', max(mb_strlen($value) - 3, 0));
    }
}
