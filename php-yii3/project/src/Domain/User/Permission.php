<?php

declare(strict_types=1);

namespace App\Domain\User;

/** Имена прав — константы: опечатка станет ошибкой анализатора, а не тихим отказом. */
final class Permission
{
    public const TICKET_VIEW_ANY = 'ticket.view.any';
    public const TICKET_VIEW_OWN = 'ticket.view.own';
    public const TICKET_CREATE = 'ticket.create';
    public const TICKET_UPDATE_ANY = 'ticket.update.any';
    public const TICKET_UPDATE_OWN = 'ticket.update.own';
    public const TICKET_ASSIGN = 'ticket.assign';
    public const TICKET_DELETE = 'ticket.delete';
    public const USER_MANAGE = 'user.manage';
    public const REPORT_VIEW = 'report.view';
}
