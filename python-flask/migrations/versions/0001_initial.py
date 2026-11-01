"""Точки выдачи, модели оборудования и экземпляры.

Revision ID: 0001_initial
Revises:
"""

import sqlalchemy as sa
from alembic import op

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "stations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("address", sa.String(500), nullable=False),
        # часовой пояс точки, а не сервера: от него зависит граница суток
        # при расчёте тарифа
        sa.Column("timezone", sa.String(64), nullable=False, server_default="Europe/Moscow"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )

    op.create_table(
        "equipment_models",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("category", sa.String(20), nullable=False),
        # Numeric, а не float: двоичное представление теряет копейки
        sa.Column("daily_rate", sa.Numeric(12, 2), nullable=False),
        sa.Column("deposit", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="RUB"),
        sa.Column("description", sa.String(2000)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.CheckConstraint("daily_rate > 0", name="ck_equipment_models_rate_positive"),
        sa.CheckConstraint("deposit >= 0", name="ck_equipment_models_deposit_non_negative"),
    )
    op.create_index("ix_equipment_models_category", "equipment_models", ["category"])

    op.create_table(
        "units",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("serial", sa.String(64), nullable=False),
        sa.Column("model_id", sa.Integer(),
                  sa.ForeignKey("equipment_models.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("station_id", sa.Integer(),
                  sa.ForeignKey("stations.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("condition", sa.String(20), nullable=False, server_default="good"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        # серийный номер уникален в пределах модели: у разных производителей
        # номера совпадают
        sa.UniqueConstraint("model_id", "serial", name="uq_units_model_serial"),
    )
    op.create_index("ix_units_station", "units", ["station_id"])


def downgrade() -> None:
    op.drop_table("units")
    op.drop_table("equipment_models")
    op.drop_table("stations")
