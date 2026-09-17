<?php

declare(strict_types=1);

namespace App\Tests\Support;

use HttpSoft\Message\Response;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;

final class SpyHandler implements RequestHandlerInterface
{
    private bool $called = false;

    private ?ServerRequestInterface $received = null;

    public function __construct(private readonly int $status = 200)
    {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $this->called = true;
        $this->received = $request;

        return new Response($this->status);
    }

    public function wasCalled(): bool
    {
        return $this->called;
    }

    public function receivedRequest(): ?ServerRequestInterface
    {
        return $this->received;
    }
}
