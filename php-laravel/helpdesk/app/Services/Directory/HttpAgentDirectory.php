<?php
// app/Services/Directory/HttpAgentDirectory.php
declare(strict_types=1);

namespace App\Services\Directory;

use App\Contracts\AgentDirectory;
use App\DTO\AgentInfo;
use App\Exceptions\ExternalServiceUnavailableException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

final readonly class HttpAgentDirectory implements AgentDirectory
{
    public function __construct(
        private string $baseUrl,
        private string $apiKey,
        private int $timeout = 3,
        private int $cacheTtl = 600,
    ) {
    }

    public function find(int $userId): ?AgentInfo
    {
        return Cache::remember(
            "directory:agent:{$userId}",
            $this->cacheTtl,
            function () use ($userId): ?AgentInfo {
                $response = $this->request()->get("/agents/{$userId}");

                if ($response->status() === 404) {
                    return null;
                }

                $data = $this->handle($response)->json();

                return AgentInfo::fromArray($data);
            },
        );
    }

    public function byDepartment(string $department): array
    {
        $response = $this->request()->get('/agents', ['department' => $department]);

        return array_map(
            AgentInfo::fromArray(...),
            $this->handle($response)->json('data', []),
        );
    }

    private function request(): PendingRequest
    {
        return Http::baseUrl($this->baseUrl)
            ->withToken($this->apiKey)
            ->acceptJson()
            ->connectTimeout(1)
            ->timeout($this->timeout)
            ->retry(2, 200, fn (\Throwable $e): bool => $e instanceof ConnectionException
                || ($e instanceof RequestException && $e->response->serverError()))
            ->withUserAgent('HelpDesk/1.4 (+https://helpdesk.local)')
            ->withHeader('X-Request-Id', \Illuminate\Support\Facades\Context::get('request_id', ''));
    }

    private function handle(\Illuminate\Http\Client\Response $response): \Illuminate\Http\Client\Response
    {
        if ($response->successful()) {
            return $response;
        }

        logger()->channel('integrations')->warning('directory.error', [
            'status' => $response->status(),
            'body'   => mb_substr($response->body(), 0, 500),
        ]);

        throw new ExternalServiceUnavailableException('directory');
    }
}
