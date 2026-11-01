-- diagnostic: safe to re-run
/*
  050_window_report.sql — недельный отчёт по перевозчикам: оконные функции, WINDOW, APPROX_PERCENTILE, GROUPING SETS (урок 2.4).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

WITH weekly AS
(
    SELECT c.Code AS carrier,
           DATETRUNC(ISO_WEEK, s.CreatedAt) AS week_start,
           COUNT(*) AS shipments,
           CAST(100.0 * SUM(IIF(s.DeliveredAt > s.PromisedAt, 1, 0)) / NULLIF(COUNT(s.DeliveredAt), 0) AS decimal(5, 2)) AS late_pct,
           APPROX_PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATEDIFF(MINUTE, s.CreatedAt, s.DeliveredAt)) / 60.0 AS median_hours,
           GROUPING(DATETRUNC(ISO_WEEK, s.CreatedAt)) AS is_carrier_total
    FROM demo.Shipment AS s
    JOIN demo.Carrier AS c ON c.CarrierId = s.CarrierId
    GROUP BY GROUPING SETS ((c.Code, DATETRUNC(ISO_WEEK, s.CreatedAt)), (c.Code))
)
SELECT carrier, week_start, shipments, late_pct, CAST(median_hours AS decimal(8, 1)) AS median_hours,
       late_pct - LAG(late_pct) OVER w AS late_pct_delta,
       SUM(shipments) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_shipments,
       is_carrier_total
FROM weekly
WINDOW w AS (PARTITION BY carrier, is_carrier_total ORDER BY week_start)
ORDER BY carrier, is_carrier_total, week_start;
GO
