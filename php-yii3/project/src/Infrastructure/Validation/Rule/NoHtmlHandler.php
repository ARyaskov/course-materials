<?php

declare(strict_types=1);

namespace App\Infrastructure\Validation\Rule;

use Yiisoft\Validator\Exception\UnexpectedRuleException;
use Yiisoft\Validator\RuleHandlerInterface;
use Yiisoft\Validator\RuleInterface;
use Yiisoft\Validator\Result;
use Yiisoft\Validator\ValidationContext;

final class NoHtmlHandler implements RuleHandlerInterface
{
    public function validate(mixed $value, RuleInterface $rule, ValidationContext $context): Result
    {
        if (!$rule instanceof NoHtml) {
            throw new UnexpectedRuleException(NoHtml::class, $rule);
        }

        $result = new Result();

        if (!is_string($value)) {
            return $result->addError($rule->message);
        }

        // содержимое изменилось после удаления тегов — значит, они там были
        if (strip_tags($value) !== $value) {
            return $result->addError($rule->message);
        }

        // и сущности вида &lt;script&gt; тоже
        if (html_entity_decode($value, ENT_QUOTES | ENT_HTML5) !== $value) {
            return $result->addError($rule->message);
        }

        return $result;
    }
}
