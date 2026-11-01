SELECT room_id,
       sum(extract(epoch FROM (upper(slot) - lower(slot))) / 60)::bigint AS minutes_booked,
       count(*) AS bookings
FROM bookings
WHERE room_id = ANY(?)
  AND status IN ('PENDING', 'CONFIRMED')
  AND slot && tstzrange(?, ?, '[)')
GROUP BY room_id
