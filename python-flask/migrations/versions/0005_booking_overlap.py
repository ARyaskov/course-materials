"""Ограничение исключения: одна единица — одна бронь на пересекающийся период.

Проверка «нет ли конфликта» запросом перед вставкой не работает: два
запроса, выполненные одновременно, оба видят свободный интервал и оба
вставляют строку. Уровень изоляции READ COMMITTED этого не запрещает —
конфликтующей строки в момент проверки ещё нет.

Ограничение исключения переносит проверку в базу, где она атомарна.
Индекс GiST по диапазону времени и равенству unit_id гарантирует, что
пересечение невозможно физически, независимо от числа процессов.

Revision ID: 0005_booking_overlap
Revises: 0004_invoices
"""

from alembic import op

revision = "0005_booking_overlap"
down_revision = "0004_invoices"
branch_labels = None
depends_on = None

#: буфер на осмотр и зарядку между арендами; то же значение живёт
#: в depot.domain.rules.INSPECTION_BUFFER и продублировано здесь намеренно:
#: миграция должна оставаться воспроизводимой при изменении кода
INSPECTION_BUFFER = "2 hours"

#: статусы, при которых бронь занимает экземпляр; отменённые и истёкшие
#: в ограничение не входят, иначе повторно забронировать освободившийся
#: интервал станет невозможно
ACTIVE_STATUSES = "('pending', 'confirmed')"


def upgrade() -> None:
    # btree_gist нужен, чтобы в одном индексе сочетать проверку равенства
    # по unit_id и проверку пересечения по диапазону
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")

    op.execute(
        "ALTER TABLE bookings "
        "ADD CONSTRAINT ck_bookings_period CHECK (ends_at > starts_at)"
    )

    op.execute(
        f"""
        ALTER TABLE bookings
        ADD CONSTRAINT ex_bookings_unit_period
        EXCLUDE USING gist (
            unit_id WITH =,
            tstzrange(
                starts_at - interval '{INSPECTION_BUFFER}',
                ends_at + interval '{INSPECTION_BUFFER}',
                '[)'
            ) WITH &&
        )
        WHERE (status IN {ACTIVE_STATUSES})
        """
    )


def downgrade() -> None:
    op.execute("ALTER TABLE bookings DROP CONSTRAINT ex_bookings_unit_period")
    op.execute("ALTER TABLE bookings DROP CONSTRAINT ck_bookings_period")
    # расширение не удаляется: им могут пользоваться другие объекты схемы
