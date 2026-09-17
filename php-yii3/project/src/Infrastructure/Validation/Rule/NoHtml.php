<?php

declare(strict_types=1);

namespace App\Infrastructure\Validation\Rule;

use Attribute;
use Yiisoft\Validator\Rule\Trait\SkipOnEmptyTrait;
use Yiisoft\Validator\Rule\Trait\SkipOnErrorTrait;
use Yiisoft\Validator\RuleWithOptionsInterface;
use Yiisoft\Validator\SkipOnEmptyInterface;
use Yiisoft\Validator\SkipOnErrorInterface;

#[Attribute(Attribute::TARGET_PROPERTY | Attribute::IS_REPEATABLE)]
final class NoHtml implements RuleWithOptionsInterface, SkipOnEmptyInterface, SkipOnErrorInterface
{
    use SkipOnEmptyTrait;
    use SkipOnErrorTrait;

    public function __construct(
        public readonly string $message = 'Поле не должно содержать HTML-разметку.',
        mixed $skipOnEmpty = null,
        private readonly bool $skipOnError = false,
    ) {
        $this->skipOnEmpty = $skipOnEmpty;
    }

    public function getName(): string
    {
        return 'noHtml';
    }

    public function getOptions(): array
    {
        return ['message' => ['template' => $this->message]];
    }

    public function getHandler(): string
    {
        return NoHtmlHandler::class;
    }
}
