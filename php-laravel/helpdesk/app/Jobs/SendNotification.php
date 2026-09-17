<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Contracts\Notifier;
use App\Models\User;
use App\Services\Notifications\NotifierFactory;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

final class SendNotification implements ShouldQueue
{
    use Queueable;

    public int $tries = 5;

    public function __construct(
        public readonly string $channel,
        public readonly int $userId,
        public readonly string $subject,
        public readonly string $body,
    ) {
        $this->onQueue('notifications');
    }

    public function handle(NotifierFactory $factory): void
    {
        $user = User::query()->find($this->userId);

        if ($user === null) {
            return;   // пользователя удалили, пока задача ждала очереди
        }

        $notifier = $factory->byChannel($this->channel);

        if (! $notifier instanceof Notifier || ! $notifier->supports($user)) {
            return;
        }

        $notifier->send($user, $this->subject, $this->body);
    }

    /** @return list<int> */
    public function backoff(): array
    {
        return [10, 30, 120, 300];
    }

    /** @return list<string> */
    public function tags(): array
    {
        return ['notify', "user:{$this->userId}", "channel:{$this->channel}"];
    }
}
