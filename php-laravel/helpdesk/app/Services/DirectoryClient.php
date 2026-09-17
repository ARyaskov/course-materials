<?php
// app/Services/DirectoryClient.php
declare(strict_types=1);

namespace App\Services;

use App\Exceptions\ExternalServiceUnavailableException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;

final readonly class DirectoryClient
{
    public function departmentOf(int $userId): ?string
    {
        try {
            return Http::timeout(3)
                ->retry(2, 200)
                ->get(config('services.directory.url') . "/users/{$userId}")
                ->throw()
                ->json('department');
        } catch (ConnectionException | RequestException $e) {
            throw new ExternalServiceUnavailableException('directory', previous: $e);
        }
    }
}
