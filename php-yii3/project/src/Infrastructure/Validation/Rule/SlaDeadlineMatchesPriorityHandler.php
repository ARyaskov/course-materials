<?php

declare(strict_types=1);

namespace App\Infrastructure\Validation\Rule;

use App\Domain\Ticket\TicketPriority;
use Yiisoft\Validator\{Result, RuleHandlerInterface, RuleInterface, ValidationContext};

final class SlaDeadlineMatchesPriorityHandler implements RuleHandlerInterface
{
    public function validate(mixed $value, RuleInterface $rule, ValidationContext $context): Result
    {
        $result = new Result();

        if ($value === null) {
            return $result;                 // срок не задан — считаем по приоритету
        }

        // доступ к соседним полям проверяемого объекта
        $priorityValue = $context->getDataSet()?->getAttributeValue('priority');
        $priority = TicketPriority::tryFrom((string) $priorityValue);

        if ($priority === null) {
            return $result;                 // приоритет невалиден — его правило и сообщит
        }

        $deadline = new \DateTimeImmutable((string) $value);
        $latest = (new \DateTimeImmutable())->modify("+{$priority->responseHours()} hours");

        if ($deadline > $latest) {
            return $result->addError(
                'Срок реакции для приоритета «{priority}» не может превышать {hours} ч.',
                parameters: ['priority' => $priority->value, 'hours' => $priority->responseHours()],
            );
        }

        return $result;
    }
}
