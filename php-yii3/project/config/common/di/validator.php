<?php

declare(strict_types=1);

use App\Infrastructure\Validation\Rule\{NotBlacklistedWordHandler, NoHtmlHandler};
use Psr\Container\ContainerInterface;
use Yiisoft\Validator\RuleHandlerResolverInterface;
use Yiisoft\Validator\RuleHandlerContainer;

return [
    // обработчики создаются контейнером, поэтому получают зависимости
    RuleHandlerResolverInterface::class => RuleHandlerContainer::class,
];
