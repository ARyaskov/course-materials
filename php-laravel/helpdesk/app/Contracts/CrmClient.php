<?php

declare(strict_types=1);

namespace App\Contracts;

use App\Models\Ticket;

interface CrmClient
{
    /** @return string внешний идентификатор заявки в CRM */
    public function pushTicket(Ticket $ticket): string;
}
