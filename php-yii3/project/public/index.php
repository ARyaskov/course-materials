<?php

declare(strict_types=1);

use App\Infrastructure\Config\SecretsRegistry;
use Psr\Log\LogLevel;
use Yiisoft\ErrorHandler\ErrorHandler;
use Yiisoft\ErrorHandler\Renderer\JsonRenderer;
use Yiisoft\Log\Logger;
use Yiisoft\Log\Target\File\FileTarget;
use Yiisoft\Yii\Runner\Http\HttpApplicationRunner;

require_once dirname(__DIR__) . '/vendor/autoload.php';

$debug = (bool) getenv('YII_DEBUG');
$environment = getenv('YII_ENV') ?: 'prod';

if ($environment === 'prod') {
    $problems = SecretsRegistry::audit();

    if ($problems !== []) {
        throw new \RuntimeException('Проблемы с секретами: ' . implode('; ', $problems));
    }
}

// обработчик на случай падения ДО того, как приложение собрано:
// иначе клиент получит пустой ответ или HTML от PHP
$temporary = new ErrorHandler(
    new Logger([(new FileTarget('php://stderr'))
        ->setLevels([LogLevel::EMERGENCY, LogLevel::ALERT, LogLevel::ERROR])]),
    // JSON даже здесь: API не отдаёт разметку ни при каких обстоятельствах
    new JsonRenderer(),
);

(new HttpApplicationRunner(
    rootPath: dirname(__DIR__),
    debug: $debug,
    checkEvents: $debug,
    environment: $environment,
))
    ->withTemporaryErrorHandler($temporary)
    ->run();
