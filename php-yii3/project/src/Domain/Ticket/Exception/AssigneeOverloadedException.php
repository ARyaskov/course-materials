<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;
use App\Domain\User\UserId;

final class AssigneeOverloadedException extends DomainException
{
    public static function withLimit(UserId $assigneeId, int $limit): self
    {
        return new self(sprintf('У сотрудника %d уже %d открытых заявок.', $assigneeId->value, $limit));
    }

    public function errorType(): string
    {
        return 'assignee_overloaded';
    }
}
