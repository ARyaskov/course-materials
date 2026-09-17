<?php
// lang/ru/errors.php
declare(strict_types=1);

return [
    'validation_failed'         => 'Данные не прошли проверку.',
    'unauthenticated'           => 'Требуется авторизация.',
    'forbidden'                 => 'Недостаточно прав для этой операции.',
    'not_found'                 => 'Ресурс не найден.',
    'too_many_requests'         => 'Слишком много запросов. Повторите позже.',
    'server_error'              => 'Внутренняя ошибка сервера.',
    'ticket_already_closed'     => 'Заявка №:id уже закрыта.',
    'ticket_limit_exceeded'     => 'Превышен лимит открытых заявок: :current из :limit.',
    'invalid_status_transition' => 'Переход :from → :to недопустим.',
];
