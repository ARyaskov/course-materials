"""Пользователи, сессии обновления и ключи идемпотентности.

Revision ID: 0002_users_auth
Revises: 0001_initial
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002_users_auth"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("full_name", sa.String(200), nullable=False),
        sa.Column("role", sa.String(20), nullable=False, server_default="client"),
        sa.Column("station_id", sa.Integer(),
                  sa.ForeignKey("stations.id", ondelete="RESTRICT")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        # момент смены пароля попадает в токен и служит массовым отзывом:
        # все токены, выданные раньше, перестают приниматься
        sa.Column("password_changed_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        # оператор привязан к точке, клиент и администратор — нет
        sa.CheckConstraint(
            "(role = 'operator') = (station_id is not null)",
            name="operator_has_station",
        ),
    )

    # Уникальность без учёта регистра: Ivanov@example.com и ivanov@example.com —
    # один и тот же адрес. Функциональный индекс, а не UNIQUE по колонке:
    # иначе регистр создаёт две учётные записи.
    op.execute(
        "CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email))"
    )

    op.create_table(
        "refresh_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        # хранится хеш, а не значение: утечка таблицы не даёт войти
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("user_agent", sa.String(255)),
        sa.Column("ip", sa.String(45)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )
    op.create_index("ix_refresh_sessions_user", "refresh_sessions", ["user_id"])
    op.create_index("ix_refresh_sessions_expires", "refresh_sessions", ["expires_at"])

    op.create_table(
        "idempotency_records",
        sa.Column("key", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        # отпечаток тела: тот же ключ с другим телом — ошибка клиента,
        # а не повтор
        sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("response_body", postgresql.JSONB(), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )
    op.create_index(
        "ix_idempotency_created", "idempotency_records", ["created_at"]
    )


def downgrade() -> None:
    op.drop_table("idempotency_records")
    op.drop_table("refresh_sessions")
    op.execute("DROP INDEX IF EXISTS uq_users_email_lower")
    op.drop_table("users")
