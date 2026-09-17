<?php
// Демонстрация из урока 3.2: файл БЕЗ declare(strict_types=1).
// Режим типов определяется файлом, откуда сделан вызов, поэтому строка '42'
// здесь проходит в параметр int. Это иллюстрация, а не часть приложения.

require __DIR__ . '/../vendor/autoload.php';

use App\Domain\Ticket\TicketId;

$id = new TicketId('42');  // сработает: вызывающий файл в слабом режиме
var_dump($id->value);      // int(42)
