<?php

declare(strict_types=1);

namespace App\Api\Event;

use Psr\Http\Message\ServerRequestInterface;

/** Техническое событие фреймворка: живёт в Api, а не в Domain. */
final readonly class RequestStarted
{
    public function __construct(public ServerRequestInterface $request)
    {
    }
}
