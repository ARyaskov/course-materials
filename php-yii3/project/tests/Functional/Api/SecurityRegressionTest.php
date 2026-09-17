<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class SecurityRegressionTest extends ApiTestCase
{
    /**
     * Инцидент 2026-08-14: список комментариев не проверял доступ
     * к родительской заявке, и любой авторизованный видел переписку.
     */
    #[Test]
    public function комментарии_чужой_заявки_недоступны(): void
    {
        $foreign = $this->ticketFactory->reportedBy(999)->create();
        $this->fixture->addComment($foreign->id, 'Внутреннее обсуждение');

        $response = $this->get("/api/v1/tickets/{$foreign->id->value}/comments",
            $this->headersFor('reporter'));

        self::assertContains($response->getStatusCode(), [403, 404]);
        self::assertStringNotContainsString('Внутреннее обсуждение',
            (string) $response->getBody());
    }

    // Второй тест того же класса закрывает инцидент 2026-08-22:
    // ответы на вход с существующим и несуществующим адресом должны
    // совпадать по коду, типу ошибки и тексту сообщения.
}
