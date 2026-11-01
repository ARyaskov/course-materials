"""Брони, аренды и акты повреждения.

Ограничение на пересечение периодов добавляется отдельной ревизией
(0005): оно требует расширения btree_gist и заслуживает собственной
записи в истории.

Revision ID: 0003_bookings_rentals
Revises: 0002_users_auth
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0003_bookings_rentals"
down_revision = "0002_users_auth"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "bookings",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("unit_id", sa.Integer(),
                  sa.ForeignKey("units.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("hold_expires_at", sa.DateTime(timezone=True)),
        sa.Column("total", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="RUB"),
        sa.Column("note", sa.String(500)),
        sa.Column("cancel_reason", sa.String(500)),
        sa.Column("payment_hold_id", sa.String(64)),
        sa.Column("notification_pending", sa.Boolean(), nullable=False,
                  server_default=sa.text("false")),
        # счётчик версии для оптимистической блокировки: два одновременных
        # изменения одной брони не должны затирать друг друга молча
        sa.Column("version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )
    op.create_index("ix_bookings_status", "bookings", ["status"])
    op.create_index("ix_bookings_user", "bookings", ["user_id"])

    # Частичный индекс под самый частый запрос: активные брони одного
    # экземпляра. Он вчетверо меньше полного, потому что завершённые
    # и отменённые брони в него не входят.
    op.execute(
        """
        CREATE INDEX ix_bookings_active_period
        ON bookings (unit_id, starts_at, ends_at)
        WHERE status IN ('pending', 'confirmed')
        """
    )

    op.create_table(
        "rentals",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("booking_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("bookings.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("returned_at", sa.DateTime(timezone=True)),
        sa.Column("issued_by", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        # одна выдача на бронь: повторная выдача по тому же документу —
        # ошибка, а не сценарий
        sa.UniqueConstraint("booking_id", name="uq_rentals_booking"),
        sa.CheckConstraint(
            "returned_at is null or returned_at >= issued_at",
            name="return_after_issue",
        ),
    )

    # Частичный индекс под фоновую задачу начисления штрафов: она ищет
    # незакрытые аренды с истёкшим сроком, и закрытые ей не нужны
    op.execute(
        """
        CREATE INDEX ix_rentals_overdue ON rentals (due_at)
        WHERE returned_at is null
        """
    )

    op.create_table(
        "damage_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("rental_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("rentals.id", ondelete="CASCADE"), nullable=False),
        sa.Column("description", sa.String(2000), nullable=False),
        sa.Column("severity", sa.String(20), nullable=False),
        sa.Column("estimated_cost", sa.Numeric(12, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )

    op.create_table(
        "damage_photos",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("report_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("damage_reports.id", ondelete="CASCADE"), nullable=False),
        sa.Column("storage_key", sa.String(500), nullable=False, unique=True),
        sa.Column("original_name", sa.String(255), nullable=False),
        sa.Column("media_type", sa.String(64), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("checksum", sa.String(64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )


def downgrade() -> None:
    op.drop_table("damage_photos")
    op.drop_table("damage_reports")
    op.execute("DROP INDEX IF EXISTS ix_rentals_overdue")
    op.drop_table("rentals")
    op.execute("DROP INDEX IF EXISTS ix_bookings_active_period")
    op.drop_table("bookings")
