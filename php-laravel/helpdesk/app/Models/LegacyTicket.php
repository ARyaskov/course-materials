<?php
// app/Models/LegacyTicket.php
declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class LegacyTicket extends Model
{
    protected $table = 'tbl_support_requests';   // унаследованная схема
    protected $primaryKey = 'request_id';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;                   // нет created_at/updated_at
    protected $connection = 'legacy';
}
