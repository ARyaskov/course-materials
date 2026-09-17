<?php

declare(strict_types=1);

use App\Api\Action\{Admin, Auth, Report, System, Ticket};
use App\Api\Middleware\{AuthMiddleware, InputMiddleware,
                        LoginRateLimitMiddleware, RequirePermissionMiddleware};
use App\Application\Ticket\{AssignTicketInput, ChangeStatusInput,
                            CreateTicketInput, UpdateTicketInput};
use App\Application\Auth\LoginInput;
use App\Domain\User\Permission;
use Yiisoft\Injector\Injector;
use Yiisoft\Router\{Group, Route};

/** Фабрика middleware валидации: класс DTO задаётся параметром. */
$input = static fn (string $inputClass): callable
    => static fn (Injector $injector): InputMiddleware
        => $injector->make(InputMiddleware::class, ['inputClass' => $inputClass]);

/** Фабрика middleware проверки права. */
$require = static fn (string $permission): callable
    => static fn (Injector $injector): RequirePermissionMiddleware
        => $injector->make(RequirePermissionMiddleware::class, ['permission' => $permission]);

return [
    // ---------- публично: мониторинг не должен знать токенов ----------
    Route::get('/api/v1/health')->action(System\HealthAction::class)->name('api/v1/health'),
    Route::get('/api/v1/version')->action(System\VersionAction::class)->name('api/v1/version'),

    Group::create('/api/v1')
        ->namePrefix('api/v1/')
        ->routes(
            // ---------- публично: здесь токен выдают ----------
            Group::create('/auth')->namePrefix('auth/')->routes(
                Route::post('/login')
                    ->middleware(LoginRateLimitMiddleware::class)
                    ->middleware($input(LoginInput::class))
                    ->action(Auth\LoginAction::class)->name('login'),

                Route::post('/refresh')
                    ->action(Auth\RefreshAction::class)->name('refresh'),
            ),

            // ---------- всё остальное — только с токеном ----------
            Group::create('')
                ->middleware(AuthMiddleware::class)
                ->routes(
                    Route::post('/auth/logout')
                        ->action(Auth\LogoutAction::class)->name('auth/logout'),

                    Route::get('/me')->action(User\MeAction::class)->name('me'),

                    // ---------- заявки ----------
                    Group::create('/tickets')->namePrefix('tickets/')->routes(
                        Route::get('')
                            ->action(Ticket\ListTicketsAction::class)->name('index'),

                        Route::post('')
                            ->middleware($input(CreateTicketInput::class))
                            ->action(Ticket\CreateTicketAction::class)->name('create'),

                        Route::get('/{id:\d+}')
                            ->action(Ticket\ViewTicketAction::class)->name('view'),

                        Route::patch('/{id:\d+}')
                            ->middleware($input(UpdateTicketInput::class))
                            ->action(Ticket\UpdateTicketAction::class)->name('update'),

                        Route::delete('/{id:\d+}')
                            ->middleware($require(Permission::TICKET_DELETE))
                            ->action(Ticket\DeleteTicketAction::class)->name('delete'),

                        Route::post('/{id:\d+}/assign')
                            ->middleware($require(Permission::TICKET_ASSIGN))
                            ->middleware($input(AssignTicketInput::class))
                            ->action(Ticket\AssignTicketAction::class)->name('assign'),

                        Route::post('/{id:\d+}/status')
                            ->middleware($input(ChangeStatusInput::class))
                            ->action(Ticket\ChangeStatusAction::class)->name('status'),

                        Route::get('/{id:\d+}/comments')
                            ->action(Ticket\ListCommentsAction::class)->name('comments/index'),

                        Route::post('/{id:\d+}/comments')
                            ->middleware($input(AddCommentInput::class))
                            ->action(Ticket\AddCommentAction::class)->name('comments/create'),

                        Route::post('/{id:\d+}/attachments')
                            ->action(Ticket\UploadAttachmentAction::class)->name('attachments'),
                    ),

                    Route::get('/attachments/{id:\d+}')
                        ->action(Ticket\DownloadAttachmentAction::class)
                        ->name('attachments/download'),

                    // ---------- отчёты и администрирование ----------
                    // Group::create('/reports')->middleware($require(Permission::REPORT_VIEW))
                    //   summary, export, export/{id}
                    // Group::create('/admin')->middleware($require(Permission::USER_MANAGE))
                    //   users, users/create, users/{id}/role
                ),
        ),
];
