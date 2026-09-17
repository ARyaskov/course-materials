<?php

declare(strict_types=1);

namespace App\Tests\Support;

use HttpSoft\Message\Response;
use HttpSoft\Message\Stream;
use Psr\Http\Client\ClientExceptionInterface;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestInterface;
use Psr\Http\Message\ResponseInterface;

final class StubHttpClient implements ClientInterface
{
    /** @var list<ResponseInterface|ClientExceptionInterface> */
    private array $queue = [];

    /** @var list<RequestInterface> */
    private array $received = [];

    public function willRespond(int $status, array $body = []): self
    {
        $this->queue[] = new Response(
            $status,
            ['Content-Type' => 'application/json'],
            Stream::create(json_encode($body, JSON_THROW_ON_ERROR)),
        );

        return $this;
    }

    public function willFail(ClientExceptionInterface $e): self
    {
        $this->queue[] = $e;

        return $this;
    }

    public function sendRequest(RequestInterface $request): ResponseInterface
    {
        $this->received[] = $request;

        $next = array_shift($this->queue)
            ?? throw new \LogicException('Незапланированный HTTP-запрос: '
                . $request->getUri());

        if ($next instanceof ClientExceptionInterface) {
            throw $next;
        }

        return $next;
    }

    public function requestCount(): int
    {
        return count($this->received);
    }
}
