<?php
// tests/Datasets/InvalidPayloads.php
declare(strict_types=1);

dataset('недопустимые данные заявки', [
    'пустой запрос'      => [[], ['subject', 'body']],
    'короткая тема'      => [['subject' => 'кор', 'body' => 'Достаточно длинный текст'], ['subject']],
    'длинная тема'       => [['subject' => str_repeat('a', 300), 'body' => 'Достаточно длинный текст'], ['subject']],
    'короткий текст'     => [['subject' => 'Не работает VPN', 'body' => 'кор'], ['body']],
    'неверный приоритет' => [['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст', 'priority' => 'urgent'], ['priority']],
    'запрещённый статус' => [['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст', 'status' => 'closed'], ['status']],
    'слишком много меток'=> [['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст', 'tags' => ['a','b','c','d','e','f']], ['tags']],
]);
