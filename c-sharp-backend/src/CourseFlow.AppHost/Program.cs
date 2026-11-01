// CourseFlow.AppHost (Глава 21): один `dotnet run` поднимает инфраструктуру в контейнерах,
// API и Dashboard с логами, трейсами и метриками всех компонентов.

var builder = DistributedApplication.CreateBuilder(args);

// --- Инфраструктура ---

var postgres = builder.AddPostgres("postgres")
    .WithDataVolume("courseflow-postgres-data")   // данные переживают перезапуск
    .WithPgAdmin();                               // pgAdmin UI в Dashboard

// Имя ресурса = имя connection string в API: ConnectionStrings__courseflow
var courseflowDb = postgres.AddDatabase("courseflow");

var redis = builder.AddRedis("redis")
    .WithRedisInsight();                          // Redis Insight UI

var rabbitmq = builder.AddRabbitMQ("rabbitmq")
    .WithDataVolume("courseflow-rabbitmq-data")
    .WithManagementPlugin();                      // Management UI

// --- API ---

var api = builder.AddProject<Projects.CourseFlow_Api>("courseflow-api")
    .WithReference(courseflowDb)                  // → ConnectionStrings__courseflow
    .WithReference(redis)                         // → ConnectionStrings__redis
    .WithReference(rabbitmq)                      // → ConnectionStrings__rabbitmq
    .WaitFor(courseflowDb)                        // ждём готовности БД
    .WaitFor(redis)
    .WaitFor(rabbitmq)                            // и брокера
    .WithEnvironment("Jwt__SecretKey", builder.Configuration["JwtSecret"]
        ?? "aspire-dev-only-secret-key-change-me-0123456789abcdef")
    .WithEnvironment("Seed__Enabled", "true")
    .WithHttpEndpoint(port: 8080, name: "http")
    .WithHttpHealthCheck("/health/ready");

builder.Build().Run();
