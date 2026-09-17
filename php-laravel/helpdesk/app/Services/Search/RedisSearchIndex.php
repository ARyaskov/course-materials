<?php

declare(strict_types=1);

namespace App\Services\Search;

use App\Contracts\SearchIndex;
use Illuminate\Redis\RedisManager;

final readonly class RedisSearchIndex implements SearchIndex
{
    public function __construct(
        private RedisManager $redis,
        private string $prefix = 'search:tickets',
    ) {
    }

    public function index(int $ticketId, string $subject, string $body): void
    {
        $this->redis->connection()->hset(
            $this->prefix,
            (string) $ticketId,
            json_encode([
                'subject' => $subject,
                'body' => mb_substr($body, 0, 500),
            ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        );
    }

    public function remove(int $ticketId): void
    {
        $this->redis->connection()->hdel($this->prefix, (string) $ticketId);
    }

    /** @return list<int> */
    public function search(string $query, int $limit = 50): array
    {
        $found = [];
        $needle = mb_strtolower($query);

        foreach ($this->redis->connection()->hgetall($this->prefix) as $id => $raw) {
            $row = json_decode((string) $raw, true, 512, JSON_THROW_ON_ERROR);

            if (str_contains(mb_strtolower((string) $row['subject']), $needle)) {
                $found[] = (int) $id;
            }

            if (count($found) >= $limit) {
                break;
            }
        }

        return $found;
    }
}
