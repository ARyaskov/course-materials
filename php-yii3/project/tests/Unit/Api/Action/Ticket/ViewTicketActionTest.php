<?php

declare(strict_types=1);

namespace App\Tests\Unit\Api\Action\Ticket;

use App\Api\Action\Ticket\ViewTicketAction;
use App\Api\Middleware\AuthMiddleware;
use App\Tests\Support\InMemoryTicketRepository;
use HttpSoft\Message\{ServerRequest, StreamFactory};
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class ViewTicketActionTest extends TestCase
{
    #[Test]
    public function отдаёт_заявку_по_идентификатору(): void
    {
        // ни веб-сервера, ни суперглобальных массивов
        $request = (new ServerRequest(method: 'GET', uri: '/api/v1/tickets/1042'))
            ->withHeader('Accept', 'application/json')
            ->withAttribute(AuthMiddleware::USER_ID, 7);

        $action = new ViewTicketAction(
            InMemoryTicketRepository::withTicket(id: 1042),
            $this->responseFactory(),
        );

        $response = $action($this->currentRouteWith(['id' => '1042']));

        self::assertSame(200, $response->getStatusCode());
        self::assertStringContainsString('1042', (string) $response->getBody());
    }

    #[Test]
    public function тело_запроса_собирается_из_потока(): void
    {
        $request = (new ServerRequest(method: 'POST', uri: '/api/v1/tickets'))
            ->withHeader('Content-Type', 'application/json')
            ->withBody((new StreamFactory())->createStream(
                json_encode(['title' => 'Не открывается VPN'], JSON_THROW_ON_ERROR),
            ));

        self::assertSame('application/json', $request->getHeaderLine('Content-Type'));
        self::assertStringContainsString('VPN', (string) $request->getBody());
    }
}
