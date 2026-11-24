-- ============================================================================
--  VALIDATION - cek konsistensi OLTP vs data warehouse dan KPI
--  Cara pakai: psql -U postgres -d airline -f database/validation.sql
-- ============================================================================

\echo '=== 1. ROW COUNT: OLTP vs DW ==='
SELECT 'oltp.flights' AS object, COUNT(*) AS rows FROM oltp.flights
UNION ALL SELECT 'dw.fact_flight', COUNT(*) FROM dw.fact_flight
UNION ALL SELECT 'dw.fact_daily_country_snapshot', COUNT(*) FROM dw.fact_daily_country_snapshot
UNION ALL SELECT 'dw.dim_airport (all versions)', COUNT(*) FROM dw.dim_airport
UNION ALL SELECT 'dw.dim_airport (current)', COUNT(*) FROM dw.dim_airport WHERE is_current
UNION ALL SELECT 'dw.dim_passenger', COUNT(*) FROM dw.dim_passenger
UNION ALL SELECT 'dw.dim_pilot', COUNT(*) FROM dw.dim_pilot;

\echo '=== 2. RECONCILIATION: fact vs snapshot ==='
SELECT (SELECT COUNT(*) FROM dw.fact_flight) AS fact_flights,
       (SELECT SUM(flight_count) FROM dw.fact_daily_country_snapshot) AS snapshot_flights,
       (SELECT SUM(passenger_count) FROM dw.fact_flight) AS fact_passengers,
       (SELECT SUM(passenger_count) FROM dw.fact_daily_country_snapshot) AS snapshot_passengers;

\echo '=== 3. ORPHAN / REFERENTIAL INTEGRITY ==='
SELECT 'fact_flight -> dim_airport' AS check_name, COUNT(*) AS violations
FROM dw.fact_flight f LEFT JOIN dw.dim_airport a USING (airport_key) WHERE a.airport_key IS NULL
UNION ALL
SELECT 'fact_flight -> dim_country', COUNT(*)
FROM dw.fact_flight f LEFT JOIN dw.dim_country c USING (country_key) WHERE c.country_key IS NULL
UNION ALL
SELECT 'fact_flight -> dim_passenger', COUNT(*)
FROM dw.fact_flight f LEFT JOIN dw.dim_passenger p USING (passenger_key) WHERE p.passenger_key IS NULL
UNION ALL
SELECT 'fact_flight -> dim_pilot', COUNT(*)
FROM dw.fact_flight f LEFT JOIN dw.dim_pilot p USING (pilot_key) WHERE p.pilot_key IS NULL
UNION ALL
SELECT 'fact_flight -> dim_date', COUNT(*)
FROM dw.fact_flight f LEFT JOIN dw.dim_date d ON d.date_key = f.flight_date_key WHERE d.date_key IS NULL;

\echo '=== 4. SCD TYPE 2: versi bandara ==='
SELECT COUNT(*) FILTER (WHERE version > 1) AS rows_in_new_versions,
       COUNT(DISTINCT airport_id) FILTER (WHERE version > 1) AS airports_with_history
FROM dw.dim_airport;

SELECT airport_id, airport_name, valid_from, valid_to, is_current, version
FROM dw.dim_airport
WHERE iata_code IN ('CGK', 'DPS', 'SUB', 'JOG')
  AND country_code = 'ID'
ORDER BY iata_code, version;

\echo '=== 5. SCD TYPE 2: setiap flight memakai versi yang berlaku pada tanggalnya ==='
SELECT COUNT(*) AS flights_with_wrong_version
FROM dw.fact_flight f
JOIN dw.dim_airport a USING (airport_key)
JOIN dw.dim_date d ON d.date_key = f.flight_date_key
WHERE d.full_date NOT BETWEEN a.valid_from AND a.valid_to;

\echo '=== 6. SCD TYPE 1: nama negara sudah dikoreksi dan berlaku untuk seluruh histori ==='
SELECT c.country_code, c.country_name, COUNT(*) AS flights
FROM dw.fact_flight f JOIN dw.dim_country c USING (country_key)
WHERE c.country_code = 'TR'
GROUP BY 1, 2;

\echo '=== 7. KPI UTAMA ==='
SELECT COUNT(*) AS total_flights,
       SUM(is_operated) AS operated_flights,
       SUM(is_on_time) AS on_time_flights,
       SUM(is_delayed) AS delayed_flights,
       SUM(is_cancelled) AS cancelled_flights,
       ROUND(100.0 * SUM(is_on_time) / SUM(is_operated), 2) AS on_time_rate_pct,
       ROUND(100.0 * SUM(is_delayed) / SUM(is_operated), 2) AS delay_rate_pct,
       ROUND(100.0 * SUM(is_cancelled) / COUNT(*), 2) AS cancellation_rate_pct
FROM dw.fact_flight;

\echo '=== 8. KPI BULANAN ==='
SELECT * FROM dw.v_monthly_kpi ORDER BY month_number;

\echo '=== 9. TOP 10 BANDARA ==='
SELECT * FROM dw.v_airport_kpi ORDER BY total_flights DESC LIMIT 10;
