"""Счета, строки счетов, задания импорта и журнал действий.

Revision ID: 0004_invoices
Revises: 0003_bookings_rentals
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0004_invoices"
down_revision = "0003_bookings_rentals"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "invoices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("booking_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("bookings.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="draft"),
        sa.Column("total", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="RUB"),
        sa.Column("issued_at", sa.DateTime(timezone=True)),
        sa.Column("paid_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        # один счёт на бронь: второй означал бы двойное выставление
        sa.UniqueConstraint("booking_id", name="uq_invoices_booking"),
    )

    op.create_table(
        "invoice_lines",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("invoices.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        # сутки, за которые начислена строка; для строк без привязки
        # к дате остаётся пустым
        sa.Column("day", sa.DateTime(timezone=True)),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("description", sa.String(500), nullable=False),
    )

    # Двойное начисление штрафа предотвращается ограничением, а не
    # аккуратностью кода: два воркера, обработавшие одну аренду
    # одновременно, оба пройдут любую проверку в приложении.
    op.create_index(
        "uq_invoice_lines_kind_day",
        "invoice_lines",
        ["invoice_id", "kind", "day"],
        unique=True,
        postgresql_where=sa.text("day is not null"),
    )

    op.create_table(
        "import_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="queued"),
        sa.Column("file_key", sa.String(500), nullable=False),
        sa.Column("total_rows", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("processed_rows", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("succeeded", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("failed", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("errors", postgresql.JSONB(), nullable=False,
                  server_default=sa.text("'[]'")),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("finished_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )

    op.create_table(
        "audit_records",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        # действие могло быть выполнено системой: тогда автора нет
        sa.Column("actor_id", sa.Integer(), sa.ForeignKey("users.id")),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("target_type", sa.String(32), nullable=False),
        sa.Column("target_id", sa.String(64), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False,
                  server_default=sa.text("'{}'")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )
    op.create_index("ix_audit_records_action", "audit_records", ["action"])
    op.create_index(
        "ix_audit_records_target", "audit_records", ["target_type", "target_id"]
    )


def downgrade() -> None:
    op.drop_table("audit_records")
    op.drop_table("import_jobs")
    op.drop_index("uq_invoice_lines_kind_day", table_name="invoice_lines")
    op.drop_table("invoice_lines")
    op.drop_table("invoices")
