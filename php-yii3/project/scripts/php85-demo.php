<?php

declare(strict_types=1);

// Оператор конвейера: значение слева передаётся первым аргументом функции справа.
// В HelpDesk он пригодится там, где иначе появляется цепочка вложенных вызовов.
$slug = '  Не открывается VPN  '
    |> trim(...)
    |> mb_strtolower(...)
    |> (static fn (string $s): string => preg_replace('/[^\p{L}\d]+/u', '-', $s))
    |> (static fn (string $s): string => trim($s, '-'));

var_dump($slug);   // string(21) "не-открывается-vpn"

// array_first() и array_last(): без reset()/end() и без порчи внутреннего указателя
$statuses = ['open', 'in_progress', 'closed'];

var_dump(array_first($statuses), array_last($statuses));   // "open", "closed"

// #[\NoDiscard]: возвращаемое значение нельзя игнорировать молча
final class TicketQuery
{
    #[\NoDiscard('Результат withStatus() нужно использовать: объект неизменяем')]
    public function withStatus(string $status): static
    {
        $clone = clone $this;
        // ...
        return $clone;
    }
}
