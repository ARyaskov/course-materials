<?php

declare(strict_types=1);

$errors = [];

if (PHP_VERSION_ID < 80500) {
    $errors[] = sprintf('PHP %s: требуется 8.5+', PHP_VERSION);
}

foreach (['pdo_pgsql', 'mbstring', 'intl', 'json', 'openssl', 'curl'] as $ext) {
    if (!extension_loaded($ext)) {
        $errors[] = "Расширение {$ext} не загружено";
    }
}

if (!extension_loaded('opcache')) {
    $errors[] = 'OPcache выключен: в проде это трёхкратная потеря скорости';
}

// mbstring должен реально работать, а не просто присутствовать
if (extension_loaded('mbstring') && mb_strlen('Заявка') !== 6) {
    $errors[] = 'mbstring работает неверно: проверьте mbstring.internal_encoding';
}

$required = ['memory_limit' => '128M', 'max_execution_time' => '0'];

foreach ($required as $ini => $expected) {
    printf("%-20s %s\n", $ini, ini_get($ini));
}

if ($errors !== []) {
    fwrite(STDERR, "ОКРУЖЕНИЕ НЕ ГОТОВО:\n  " . implode("\n  ", $errors) . "\n");

    exit(1);
}

fwrite(STDOUT, "Окружение готово: PHP " . PHP_VERSION . "\n");

exit(0);
