<?php
// направление: несколько ролей у пользователя
// database/migrations/..._create_role_user_table.php
declare(strict_types=1);

Schema::create('role_user', function (Blueprint $table): void {
    $table->foreignIdFor(User::class)->constrained()->cascadeOnDelete();
    $table->string('role', 20);
    $table->primary(['user_id', 'role']);
});
