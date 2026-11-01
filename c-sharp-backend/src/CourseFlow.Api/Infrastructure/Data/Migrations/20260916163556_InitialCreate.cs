using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace CourseFlow.Api.Infrastructure.Data.Migrations;

/// <inheritdoc />
public partial class _20260916163556_InitialCreate : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AlterDatabase()
            .Annotation("Npgsql:PostgresExtension:pg_trgm", ",,");

        migrationBuilder.CreateTable(
            name: "inbox_state",
            columns: table => new
            {
                id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                message_id = table.Column<Guid>(type: "uuid", nullable: false),
                consumer_id = table.Column<Guid>(type: "uuid", nullable: false),
                lock_id = table.Column<Guid>(type: "uuid", nullable: false),
                row_version = table.Column<byte[]>(type: "bytea", rowVersion: true, nullable: true),
                received = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                receive_count = table.Column<int>(type: "integer", nullable: false),
                expiration_time = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                consumed = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                delivered = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                last_sequence_number = table.Column<long>(type: "bigint", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_inbox_state", x => x.id);
                table.UniqueConstraint("ak_inbox_state_message_id_consumer_id", x => new { x.message_id, x.consumer_id });
            });

        migrationBuilder.CreateTable(
            name: "outbox_state",
            columns: table => new
            {
                outbox_id = table.Column<Guid>(type: "uuid", nullable: false),
                lock_id = table.Column<Guid>(type: "uuid", nullable: false),
                row_version = table.Column<byte[]>(type: "bytea", rowVersion: true, nullable: true),
                created = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                delivered = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                last_sequence_number = table.Column<long>(type: "bigint", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_outbox_state", x => x.outbox_id);
            });

        migrationBuilder.CreateTable(
            name: "users",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                password_hash = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                first_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                last_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                role = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                is_active = table.Column<bool>(type: "boolean", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_users", x => x.id);
            });

        migrationBuilder.CreateTable(
            name: "outbox_message",
            columns: table => new
            {
                sequence_number = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                enqueue_time = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                sent_time = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                headers = table.Column<string>(type: "text", nullable: true),
                properties = table.Column<string>(type: "text", nullable: true),
                inbox_message_id = table.Column<Guid>(type: "uuid", nullable: true),
                inbox_consumer_id = table.Column<Guid>(type: "uuid", nullable: true),
                outbox_id = table.Column<Guid>(type: "uuid", nullable: true),
                message_id = table.Column<Guid>(type: "uuid", nullable: false),
                content_type = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                message_type = table.Column<string>(type: "text", nullable: false),
                body = table.Column<string>(type: "text", nullable: false),
                conversation_id = table.Column<Guid>(type: "uuid", nullable: true),
                correlation_id = table.Column<Guid>(type: "uuid", nullable: true),
                initiator_id = table.Column<Guid>(type: "uuid", nullable: true),
                request_id = table.Column<Guid>(type: "uuid", nullable: true),
                source_address = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                destination_address = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                response_address = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                fault_address = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                expiration_time = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_outbox_message", x => x.sequence_number);
                table.ForeignKey(
                    name: "fk_outbox_message_inbox_state_inbox_message_id_inbox_consumer_",
                    columns: x => new { x.inbox_message_id, x.inbox_consumer_id },
                    principalTable: "inbox_state",
                    principalColumns: new[] { "message_id", "consumer_id" });
                table.ForeignKey(
                    name: "fk_outbox_message_outbox_state_outbox_id",
                    column: x => x.outbox_id,
                    principalTable: "outbox_state",
                    principalColumn: "outbox_id");
            });

        migrationBuilder.CreateTable(
            name: "courses",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                description = table.Column<string>(type: "character varying(5000)", maxLength: 5000, nullable: false),
                author_id = table.Column<Guid>(type: "uuid", nullable: false),
                price = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                published_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                thumbnail_url = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_courses", x => x.id);
                table.ForeignKey(
                    name: "fk_courses_users_author_id",
                    column: x => x.author_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Restrict);
            });

        migrationBuilder.CreateTable(
            name: "notifications",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                body = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                type = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                is_read = table.Column<bool>(type: "boolean", nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                read_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                action_url = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_notifications", x => x.id);
                table.ForeignKey(
                    name: "fk_notifications_users_user_id",
                    column: x => x.user_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "refresh_tokens",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                revoked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_refresh_tokens", x => x.id);
                table.ForeignKey(
                    name: "fk_refresh_tokens_users_user_id",
                    column: x => x.user_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "user_follows",
            columns: table => new
            {
                follower_id = table.Column<Guid>(type: "uuid", nullable: false),
                followed_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_user_follows", x => new { x.follower_id, x.followed_user_id });
                table.ForeignKey(
                    name: "fk_user_follows_users_followed_user_id",
                    column: x => x.followed_user_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "fk_user_follows_users_follower_id",
                    column: x => x.follower_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "enrollments",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                course_id = table.Column<Guid>(type: "uuid", nullable: false),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                payment_id = table.Column<Guid>(type: "uuid", nullable: true),
                status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                enrolled_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                completed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_enrollments", x => x.id);
                table.ForeignKey(
                    name: "fk_enrollments_courses_course_id",
                    column: x => x.course_id,
                    principalTable: "courses",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "fk_enrollments_users_user_id",
                    column: x => x.user_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "lessons",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                course_id = table.Column<Guid>(type: "uuid", nullable: false),
                title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                description = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                content_url = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                text_content = table.Column<string>(type: "text", nullable: true),
                order_index = table.Column<int>(type: "integer", nullable: false),
                duration = table.Column<TimeSpan>(type: "interval", nullable: true),
                is_free = table.Column<bool>(type: "boolean", nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_lessons", x => x.id);
                table.ForeignKey(
                    name: "fk_lessons_courses_course_id",
                    column: x => x.course_id,
                    principalTable: "courses",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "payments",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                course_id = table.Column<Guid>(type: "uuid", nullable: false),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                transaction_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                failure_reason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                completed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_payments", x => x.id);
                table.ForeignKey(
                    name: "fk_payments_courses_course_id",
                    column: x => x.course_id,
                    principalTable: "courses",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "fk_payments_users_user_id",
                    column: x => x.user_id,
                    principalTable: "users",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Restrict);
            });

        migrationBuilder.CreateTable(
            name: "lesson_progress",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false),
                enrollment_id = table.Column<Guid>(type: "uuid", nullable: false),
                lesson_id = table.Column<Guid>(type: "uuid", nullable: false),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                course_id = table.Column<Guid>(type: "uuid", nullable: false),
                status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                completed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                last_watched_seconds = table.Column<int>(type: "integer", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_lesson_progress", x => x.id);
                table.ForeignKey(
                    name: "fk_lesson_progress_enrollments_enrollment_id",
                    column: x => x.enrollment_id,
                    principalTable: "enrollments",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "fk_lesson_progress_lessons_lesson_id",
                    column: x => x.lesson_id,
                    principalTable: "lessons",
                    principalColumn: "id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "ix_courses_author_id",
            table: "courses",
            column: "author_id");

        migrationBuilder.CreateIndex(
            name: "ix_courses_status_published_at",
            table: "courses",
            columns: new[] { "status", "published_at" });

        migrationBuilder.CreateIndex(
            name: "ix_courses_title",
            table: "courses",
            column: "title")
            .Annotation("Npgsql:IndexMethod", "gin")
            .Annotation("Npgsql:IndexOperators", new[] { "gin_trgm_ops" });

        migrationBuilder.CreateIndex(
            name: "ix_enrollments_course_id",
            table: "enrollments",
            column: "course_id");

        migrationBuilder.CreateIndex(
            name: "ix_enrollments_payment_id",
            table: "enrollments",
            column: "payment_id",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_enrollments_user_id_course_id",
            table: "enrollments",
            columns: new[] { "user_id", "course_id" },
            unique: true,
            filter: "status <> 'Revoked'");

        migrationBuilder.CreateIndex(
            name: "ix_inbox_state_delivered",
            table: "inbox_state",
            column: "delivered");

        migrationBuilder.CreateIndex(
            name: "ix_lesson_progress_enrollment_id_lesson_id",
            table: "lesson_progress",
            columns: new[] { "enrollment_id", "lesson_id" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_lesson_progress_lesson_id",
            table: "lesson_progress",
            column: "lesson_id");

        migrationBuilder.CreateIndex(
            name: "ix_lesson_progress_user_id_course_id",
            table: "lesson_progress",
            columns: new[] { "user_id", "course_id" });

        migrationBuilder.CreateIndex(
            name: "ix_lessons_course_id_order_index",
            table: "lessons",
            columns: new[] { "course_id", "order_index" });

        migrationBuilder.CreateIndex(
            name: "ix_notifications_unread",
            table: "notifications",
            column: "user_id",
            filter: "is_read = false");

        migrationBuilder.CreateIndex(
            name: "ix_notifications_user_id_created_at",
            table: "notifications",
            columns: new[] { "user_id", "created_at" });

        migrationBuilder.CreateIndex(
            name: "ix_outbox_message_enqueue_time",
            table: "outbox_message",
            column: "enqueue_time");

        migrationBuilder.CreateIndex(
            name: "ix_outbox_message_expiration_time",
            table: "outbox_message",
            column: "expiration_time");

        migrationBuilder.CreateIndex(
            name: "ix_outbox_message_inbox_message_id_inbox_consumer_id_sequence_",
            table: "outbox_message",
            columns: new[] { "inbox_message_id", "inbox_consumer_id", "sequence_number" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_outbox_message_outbox_id_sequence_number",
            table: "outbox_message",
            columns: new[] { "outbox_id", "sequence_number" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_outbox_state_created",
            table: "outbox_state",
            column: "created");

        migrationBuilder.CreateIndex(
            name: "ix_payments_course_id",
            table: "payments",
            column: "course_id");

        migrationBuilder.CreateIndex(
            name: "ix_payments_user_id_created_at",
            table: "payments",
            columns: new[] { "user_id", "created_at" });

        migrationBuilder.CreateIndex(
            name: "ix_refresh_tokens_token_hash",
            table: "refresh_tokens",
            column: "token_hash",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_refresh_tokens_user_id",
            table: "refresh_tokens",
            column: "user_id");

        migrationBuilder.CreateIndex(
            name: "ix_user_follows_followed_user_id",
            table: "user_follows",
            column: "followed_user_id");

        migrationBuilder.CreateIndex(
            name: "ix_users_email",
            table: "users",
            column: "email",
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "lesson_progress");

        migrationBuilder.DropTable(
            name: "notifications");

        migrationBuilder.DropTable(
            name: "outbox_message");

        migrationBuilder.DropTable(
            name: "payments");

        migrationBuilder.DropTable(
            name: "refresh_tokens");

        migrationBuilder.DropTable(
            name: "user_follows");

        migrationBuilder.DropTable(
            name: "enrollments");

        migrationBuilder.DropTable(
            name: "lessons");

        migrationBuilder.DropTable(
            name: "inbox_state");

        migrationBuilder.DropTable(
            name: "outbox_state");

        migrationBuilder.DropTable(
            name: "courses");

        migrationBuilder.DropTable(
            name: "users");

        migrationBuilder.AlterDatabase()
            .OldAnnotation("Npgsql:PostgresExtension:pg_trgm", ",,");
    }
}
