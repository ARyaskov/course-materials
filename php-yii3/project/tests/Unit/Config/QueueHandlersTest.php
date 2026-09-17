<?php

declare(strict_types=1);

namespace App\Tests\Unit\Config;

use PHPUnit\Framework\TestCase;

/**
 * Собрано из фрагмента урока 16.3: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class QueueHandlersTest extends TestCase
{
    #[Test]
    public function все_обработчики_очереди_существуют(): void
    {
        $handlers = $this->config->get('params')['yiisoft/queue']['handlers'];

        self::assertNotSame([], $handlers);

        foreach ($handlers as $type => [$class, $method]) {
            self::assertTrue(class_exists($class), "нет класса {$class} для {$type}");
            self::assertTrue(method_exists($class, $method),
                "нет метода {$class}::{$method} для {$type}");
        }
    }
}
