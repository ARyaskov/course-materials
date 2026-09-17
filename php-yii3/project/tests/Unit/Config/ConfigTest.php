<?php

declare(strict_types=1);

namespace App\Tests\Unit\Config;

use App\Domain\Ticket\TicketRepositoryInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Yiisoft\Config\Config;
use Yiisoft\Config\ConfigPaths;
use Yiisoft\Di\Container;
use Yiisoft\Di\ContainerConfig;

final class ConfigTest extends TestCase
{
    #[Test]
    public function контейнер_собирается_в_обоих_окружениях(): void
    {
        foreach (['dev', 'prod'] as $environment) {
            $config = new Config(new ConfigPaths(dirname(__DIR__, 3), 'config'), $environment);

            $container = new Container(
                ContainerConfig::create()->withDefinitions($config->get('di-web')),
            );

            // если определение сломано, ошибка вылезет здесь, а не в проде
            self::assertInstanceOf(
                TicketRepositoryInterface::class,
                $container->get(TicketRepositoryInterface::class),
                "окружение {$environment}",
            );
        }
    }

    #[Test]
    public function все_обработчики_очереди_существуют(): void
    {
        $config = new Config(new ConfigPaths(dirname(__DIR__, 3), 'config'), 'prod');
        $handlers = $config->get('params')['yiisoft/queue']['handlers'];

        foreach ($handlers as $type => $handler) {
            [$class, $method] = $handler;

            self::assertTrue(class_exists($class), "нет класса {$class} для {$type}");
            self::assertTrue(method_exists($class, $method), "нет метода {$class}::{$method}");
        }
    }
}
