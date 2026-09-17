<?php

declare(strict_types=1);

namespace App\Api\Middleware\Security;

final readonly class InputSanitizer
{
    /** Расширения, которые разрешено принимать. Список закрытый. */
    private const ALLOWED_EXTENSIONS = ['pdf', 'png', 'jpg', 'jpeg', 'txt', 'log', 'csv'];

    /** MIME-типы, которым доверяем. Проверяется по содержимому, не по заголовку. */
    private const ALLOWED_MIME = [
        'application/pdf', 'image/png', 'image/jpeg',
        'text/plain', 'text/csv',
    ];

    public function isAllowedExtension(string $filename): bool
    {
        $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));

        return in_array($ext, self::ALLOWED_EXTENSIONS, true);
    }

    /** Тип определяется по содержимому: заголовок Content-Type клиента подделывается. */
    public function isAllowedContent(string $path): bool
    {
        $detected = (new \finfo(FILEINFO_MIME_TYPE))->file($path);

        return $detected !== false && in_array($detected, self::ALLOWED_MIME, true);
    }

    /** Имя файла для хранения: генерируем сами, клиентское не используем. */
    public function safeStorageName(string $originalName): string
    {
        $ext = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));

        return bin2hex(random_bytes(16)) . '.'
            . (in_array($ext, self::ALLOWED_EXTENSIONS, true) ? $ext : 'bin');
    }
}
