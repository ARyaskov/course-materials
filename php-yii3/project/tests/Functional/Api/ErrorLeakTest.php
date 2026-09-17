<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class ErrorLeakTest extends ApiTestCase
{
    private const FORBIDDEN_IN_RESPONSE = [
        '/app/src', 'vendor/', '.php', 'SQLSTATE', 'Exception',
        'Stack trace', 'pgsql:', 'password',
    ];

    #[Test]
    public function ответ_об_ошибке_не_раскрывает_внутренностей(): void
    {
        $this->withEnvironment('prod');

        $body = (string) $this->get('/api/v1/_boom')->getBody();

        foreach (self::FORBIDDEN_IN_RESPONSE as $needle) {
            self::assertStringNotContainsStringIgnoringCase(
                $needle, $body, "в ответе найдено: {$needle}",
            );
        }
    }

    #[Test]
    public function requestId_из_ответа_находится_в_логе(): void
    {
        $response = $this->get('/api/v1/_boom');
        $requestId = $this->json($response)['error']['requestId'];

        self::assertNotEmpty($requestId);
        self::assertLogContains('error', $requestId);
    }
}
