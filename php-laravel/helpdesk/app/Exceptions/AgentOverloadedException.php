<?php
// app/Exceptions/AgentOverloadedException.php
declare(strict_types=1);

namespace App\Exceptions;

final class AgentOverloadedException extends DomainException
{
    public function __construct(
        private readonly int $agentId,
        private readonly int $current,
        private readonly int $limit,
    ) {
        parent::__construct("У исполнителя уже {$current} открытых заявок при лимите {$limit}");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'agent_overloaded';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 409;
    }

    #[\Override]
    public function context(): array
    {
        return ['agent_id' => $this->agentId, 'current' => $this->current, 'limit' => $this->limit];
    }

    #[\Override]
    public function hint(): string
    {
        return 'Выберите другого исполнителя или дождитесь освобождения этого.';
    }
}
