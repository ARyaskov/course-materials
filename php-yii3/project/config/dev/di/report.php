<?php

use App\Domain\Report\SummaryRepositoryInterface;
use App\Infrastructure\Report\DbSummaryRepository;

return [SummaryRepositoryInterface::class => DbSummaryRepository::class];
