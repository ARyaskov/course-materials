<?php
// app/Http/Queries/TicketListQuery.php
declare(strict_types=1);

namespace App\Http\Queries;

use App\Enums\TicketStatus;
use Illuminate\Http\Request;

final readonly class TicketListQuery
{
    public const int DEFAULT_PER_PAGE = 20;
    public const int MAX_PER_PAGE = 100;

    public function __construct(
        public ?TicketStatus $status,
        public int $perPage,
        public string $sort,
        public bool $onlyMine,
    ) {
    }

    public static function fromRequest(Request $request): self
    {
        $perPage = (int) $request->integer('per_page', self::DEFAULT_PER_PAGE);

        return new self(
            status: $request->enum('status', TicketStatus::class),
            perPage: min(max($perPage, 1), self::MAX_PER_PAGE),
            sort: $request->string('sort', '-created_at')->toString(),
            onlyMine: $request->boolean('only_mine'),
        );
    }
}
