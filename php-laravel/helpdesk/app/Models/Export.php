<?php
// app/Models/Export.php
declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

final class Export extends Model
{
    use HasUuids;   // генерирует UUID v7 при создании
}
