using CourseFlow.Api.Infrastructure.Data;
using MassTransit;

namespace CourseFlow.Api.Infrastructure.Messaging;

public static class MessagingExtensions
{
    /// <summary>
    /// MassTransit + RabbitMQ + EF Core Outbox (Глава 17). Consumer-ы находятся сканированием
    /// сборки: каждый модуль объявляет свои рядом с бизнес-логикой.
    /// </summary>
    public static IServiceCollection AddMessaging(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddMassTransit(x =>
        {
            // Outbox (Глава 17.5): Publish внутри бизнес-транзакции пишет сообщение в таблицу outbox,
            // а фоновый delivery service отправляет его в брокер уже после commit.
            // Inbox на стороне consumer-а отсеивает дубликаты по MessageId.
            x.AddEntityFrameworkOutbox<AppDbContext>(o =>
            {
                o.UsePostgres();
                o.UseBusOutbox();
                o.QueryDelay = TimeSpan.FromSeconds(1);
                o.DuplicateDetectionWindow = TimeSpan.FromMinutes(30);
            });

            x.AddConsumers(typeof(MessagingExtensions).Assembly);

            // Имена очередей в kebab-case: payment-completed, enrollment-created-consumer ...
            x.SetKebabCaseEndpointNameFormatter();

            // Inbox для каждого receive endpoint: идемпотентность на уровне транспорта —
            // повторно доставленное сообщение с тем же MessageId не попадёт в consumer
            x.AddConfigureEndpointsCallback((context, _, cfg) =>
                cfg.UseEntityFrameworkOutbox<AppDbContext>(context));

            x.UsingRabbitMq((context, cfg) =>
            {
                var connectionString = configuration.GetConnectionString("rabbitmq")
                                       ?? "amqp://guest:guest@localhost:5672/";
                cfg.Host(new Uri(connectionString));

                // Retry с нарастающим интервалом; после исчерпания — очередь *_error для ручного разбора
                cfg.UseMessageRetry(r => r.Incremental(3, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2)));

                cfg.ConfigureEndpoints(context);
            });
        });

        return services;
    }
}
