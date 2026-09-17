<?php

declare(strict_types=1);

namespace App\Infrastructure\Validation\Rule;

use App\Domain\Moderation\BlacklistProviderInterface;
use Yiisoft\Validator\Exception\UnexpectedRuleException;
use Yiisoft\Validator\{Result, RuleHandlerInterface, RuleInterface, ValidationContext};

final readonly class NotBlacklistedWordHandler implements RuleHandlerInterface
{
    // зависимость приходит из контейнера — в атрибут её было бы не передать
    public function __construct(private BlacklistProviderInterface $blacklist)
    {
    }

    public function validate(mixed $value, RuleInterface $rule, ValidationContext $context): Result
    {
        if (!$rule instanceof NotBlacklistedWord) {
            throw new UnexpectedRuleException(NotBlacklistedWord::class, $rule);
        }

        $result = new Result();

        if (!is_string($value)) {
            return $result;
        }

        $found = $this->blacklist->firstMatch(mb_strtolower($value));

        return $found === null
            ? $result
            : $result->addError($rule->message, parameters: ['word' => $found]);
    }
}
