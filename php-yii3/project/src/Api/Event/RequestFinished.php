<?php

declare(strict_types=1);

namespace App\Api\Event;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;

/**
 * Факт механики приложения. На бумаге его не существует —
 * он появился вместе с решением обслуживать HTTP.
 */
final readonly class RequestFinished
{
    public function __construct(
        public ServerRequestInterface $request,
        public ResponseInterface $response,
        public float $durationMs,
    ) {
    }
}
