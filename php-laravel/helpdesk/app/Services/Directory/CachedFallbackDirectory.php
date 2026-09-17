<?php
// app/Services/Directory/CachedFallbackDirectory.php
declare(strict_types=1);

namespace App\Services\Directory;

use App\Contracts\AgentDirectory;
use App\DTO\AgentInfo;
use App\Exceptions\ExternalServiceUnavailableException;
use Illuminate\Support\Facades\Cache;

final readonly class CachedFallbackDirectory implements AgentDirectory
{
    public function __construct(private AgentDirectory $inner)
    {
    }

    public function find(int $userId): ?AgentInfo
    {
        try {
            $agent = $this->inner->find($userId);

            if ($agent !== null) {
                // держим долгоживущую копию на случай отказа
                Cache::put("directory:fallback:{$userId}", $agent, now()->addDays(7));
            }

            return $agent;
        } catch (ExternalServiceUnavailableException $e) {
            $stale = Cache::get("directory:fallback:{$userId}");

            if ($stale !== null) {
                logger()->channel('integrations')->warning('directory.stale_used', ['user' => $userId]);

                return $stale;
            }

            throw $e;
        }
    }

    public function byDepartment(string $department): array
    {
        return $this->inner->byDepartment($department);
    }
}
