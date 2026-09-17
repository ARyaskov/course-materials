<?php
// app/Http/Resources/MoneyResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Domain\Money;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Money */
final class MoneyResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'minor'     => $this->minor,
            'currency'  => $this->currency,
            'formatted' => $this->format(),
        ];
    }
}
