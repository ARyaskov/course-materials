<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Psr\EventDispatcher\EventDispatcherInterface;

final class CollectingDispatcher implements EventDispatcherInterface
{
    /** @var list<object> */
    private array $events = [];

    public function dispatch(object $event): object
    {
        $this->events[] = $event;

        return $event;
    }

    /** @return list<object> */
    public function all(): array
    {
        return $this->events;
    }

    /**
     * @param class-string $class
     * @return list<object>
     */
    public function of(string $class): array
    {
        return array_values(
            array_filter($this->events, static fn (object $e): bool => $e instanceof $class),
        );
    }
}
