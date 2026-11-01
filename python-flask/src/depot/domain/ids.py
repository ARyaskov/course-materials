"""Типы идентификаторов.

`NewType` не даёт передать идентификатор одной сущности туда, где ожидается другая.
Накладных расходов во время выполнения нет: на границе значения оборачиваются явно.
"""

from typing import NewType
from uuid import UUID

UserId = NewType("UserId", int)
StationId = NewType("StationId", int)
ModelId = NewType("ModelId", int)
UnitId = NewType("UnitId", int)

BookingId = NewType("BookingId", UUID)
RentalId = NewType("RentalId", UUID)
InvoiceId = NewType("InvoiceId", UUID)
DamageReportId = NewType("DamageReportId", UUID)
ImportJobId = NewType("ImportJobId", UUID)
