<?php
// app/Enums/EventStatus.php
declare(strict_types=1);

namespace App\Enums;

enum EventStatus: string
{
    case Draft = 'draft';           // черновик, в афише не виден
    case Published = 'published';   // опубликован, можно бронировать
    case Cancelled = 'cancelled';   // отменён организатором
    case Finished = 'finished';     // прошёл

    public function isBookable(): bool
    {
        return $this === self::Published;
    }

    public function isVisibleInCatalog(): bool
    {
        return in_array($this, [self::Published, self::Finished], strict: true);
    }
}
