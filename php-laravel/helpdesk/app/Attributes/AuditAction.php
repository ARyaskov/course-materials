<?php
// app/Attributes/AuditAction.php
declare(strict_types=1);

namespace App\Attributes;

use Attribute;

#[Attribute(Attribute::TARGET_METHOD)]
final readonly class AuditAction
{
    public function __construct(
        public string $action,
        public string $subject = 'ticket',
        public bool $storePayload = false,
    ) {
    }
}
