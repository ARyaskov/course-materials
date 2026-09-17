<?php
// app/Http/Resources/UserResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin User */
final class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            // assignee приходит через withDefault() — это несохранённая модель
            // без роли и идентификатора, поэтому обращения защищены
            'id' => $this->id,
            'name' => $this->name,
            'role' => $this->role?->value,
            // whenHas: колонка могла не попасть в выборку (author:id,name,role) —
            // в строгом режиме обращение к незагруженному атрибуту это исключение
            'email' => $this->whenHas('email', fn (string $email): mixed => $this->when(
                $request->user()?->isAgent() === true || $request->user()?->id === $this->id,
                $email,
            )),
        ];
    }
}
