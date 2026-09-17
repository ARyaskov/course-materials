<?php

declare(strict_types=1);

use Yiisoft\Rbac\Db\{AssignmentsStorage, ItemsStorage};
use Yiisoft\Rbac\{AssignmentsStorageInterface, ItemsStorageInterface,
                   Manager, ManagerInterface, RuleFactoryInterface};
use Yiisoft\Rbac\Rules\Container\RulesContainer;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Definitions\Reference;

return [
    // 1. хранилище иерархии: роли, разрешения и связи между ними
    ItemsStorageInterface::class => [
        'class' => ItemsStorage::class,
        '__construct()' => [
            'database' => Reference::to(ConnectionInterface::class),
            'tableName' => 'yii_rbac_item',
            'childrenTableName' => 'yii_rbac_item_child',
        ],
    ],

    // 2. хранилище назначений: кто какую роль имеет
    AssignmentsStorageInterface::class => [
        'class' => AssignmentsStorage::class,
        '__construct()' => [
            'database' => Reference::to(ConnectionInterface::class),
            'tableName' => 'yii_rbac_assignment',
        ],
    ],

    // 3. фабрика правил: создаёт объекты правил через контейнер,
    //    чтобы у них были зависимости
    RuleFactoryInterface::class => RulesContainer::class,

    ManagerInterface::class => [
        'class' => Manager::class,
        '__construct()' => [
            'itemsStorage' => Reference::to(ItemsStorageInterface::class),
            'assignmentsStorage' => Reference::to(AssignmentsStorageInterface::class),
            'ruleFactory' => Reference::to(RuleFactoryInterface::class),
        ],
    ],
];
