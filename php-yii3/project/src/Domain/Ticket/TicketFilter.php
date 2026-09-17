<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

final readonly class TicketFilter
{
    public const DEFAULT_LIMIT = 20;
    public const MAX_LIMIT = 100;

    /**
     * @param list<string> $statuses
     */
    public function __construct(
        public array $statuses = [],
        public ?string $priority = null,
        public ?int $assigneeId = null,
        public ?\DateTimeImmutable $createdFrom = null,
        public ?\DateTimeImmutable $createdTo = null,
        public string $search = '',
        public string $sort = '-createdAt',
        public int $limit = self::DEFAULT_LIMIT,
        public int $offset = 0,
        // НЕ из параметров запроса: заполняется только сервисом
        public ?int $onlyReporterId = null,
    ) {
    }

    /** @param array<string, mixed> $params */
    public static function fromQueryParams(array $params): self
    {
        return new self(
            // 1. белый список: неизвестные значения отсеиваются
            statuses: self::parseEnumList($params['status'] ?? null, TicketStatus::values()),

            priority: self::parseEnum($params['priority'] ?? null, TicketPriority::values()),

            // 2. приведение типа: "42abc" станет 42, "" станет 0
            assigneeId: isset($params['assigneeId']) && (int) $params['assigneeId'] > 0
                ? (int) $params['assigneeId']
                : null,

            createdFrom: self::parseDate($params['createdFrom'] ?? null),
            createdTo: self::parseDate($params['createdTo'] ?? null),

            // 3. ограничение длины: поиск по мегабайтной строке бессмыслен
            search: mb_substr(trim((string) ($params['search'] ?? '')), 0, 100),

            sort: (string) ($params['sort'] ?? '-createdAt'),

            // 4. границы: защита от ?limit=1000000
            limit: min(max((int) ($params['limit'] ?? self::DEFAULT_LIMIT), 1), self::MAX_LIMIT),
            offset: max((int) ($params['offset'] ?? 0), 0),
        );
    }

    /**
     * @param list<string> $allowed
     * @return list<string>
     */
    private static function parseEnumList(mixed $raw, array $allowed): array
    {
        if (!is_string($raw) || $raw === '') {
            return [];
        }

        // неизвестное значение молча отбрасывается: фильтр — не команда,
        // и опечатка клиента не должна ронять запрос
        return array_values(array_intersect(
            array_map(trim(...), explode(',', $raw)),
            $allowed,
        ));
    }

    /** @param list<string> $allowed */
    private static function parseEnum(mixed $raw, array $allowed): ?string
    {
        return is_string($raw) && in_array($raw, $allowed, true) ? $raw : null;
    }

    private static function parseDate(mixed $raw): ?\DateTimeImmutable
    {
        if (!is_string($raw) || $raw === '') {
            return null;
        }

        try {
            return new \DateTimeImmutable($raw);
        } catch (\Exception) {
            // некорректная дата — фильтр не применяется, а не 500
            return null;
        }
    }

    // restrictedToReporter() возвращает копию с заполненным onlyReporterId —
    // единственный способ наложить ограничение видимости, и вызывает его сервис.
}
