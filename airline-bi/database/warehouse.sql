-- ============================================================================
--  Nusantara Air - Data Warehouse (Star Schema)
--  File     : database/warehouse.sql
--  Cara pakai: psql -U postgres -d airline -f database/warehouse.sql
--
--  Grain sumber data: 1 baris = 1 passenger flight record.
--  Fact:
--    - fact_flight                     (transactional, grain = 1 flight record)
--    - fact_daily_country_snapshot     (periodic snapshot, grain = 1 negara x 1 hari)
--
--  SCD:
--    - Type 0 : dim_airport.iata_code (kode IATA tidak pernah berubah)
--    - Type 1 : dim_country.country_name (koreksi nama negara, overwrite)
--    - Type 2 : dim_airport.airport_name (perubahan nama bandara, simpan histori)
-- ============================================================================

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;
SET search_path TO dw, public;

-- ----------------------------------------------------------------------------
-- 1. DIMENSIONS
-- ----------------------------------------------------------------------------

CREATE TABLE dim_date (
    date_key       INT PRIMARY KEY,             -- YYYYMMDD
    full_date      DATE        NOT NULL UNIQUE,
    day_of_month   SMALLINT    NOT NULL,
    day_name       VARCHAR(10) NOT NULL,
    day_of_week    SMALLINT    NOT NULL,        -- 1 = Senin ... 7 = Minggu
    week_of_year   SMALLINT    NOT NULL,
    month_number   SMALLINT    NOT NULL,
    month_name     VARCHAR(10) NOT NULL,
    quarter        SMALLINT    NOT NULL,
    year           SMALLINT    NOT NULL,
    is_weekend     SMALLINT    NOT NULL CHECK (is_weekend IN (0,1)),
    month_year     VARCHAR(8)  NOT NULL
);

COMMENT ON TABLE dim_date IS 'Dimensi tanggal; date_key = YYYYMMDD';

-- SCD Type 1: koreksi nama negara menimpa nilai lama.
CREATE TABLE dim_country (
    country_key     SERIAL PRIMARY KEY,
    country_code    CHAR(2)     NOT NULL UNIQUE,
    country_name    VARCHAR(100) NOT NULL,
    continent_code  CHAR(3)     NOT NULL,
    continent_name  VARCHAR(30) NOT NULL
);

COMMENT ON TABLE  dim_country IS 'Dimensi negara; SCD1 pada country_name';
COMMENT ON COLUMN dim_country.country_name IS 'Koreksi ejaan/nama resmi menimpa nilai lama (SCD1)';

-- SCD Type 2: perubahan nama bandara disimpan sebagai versi baru.
-- SCD Type 0: iata_code tidak pernah di-update.
CREATE TABLE dim_airport (
    airport_key   SERIAL PRIMARY KEY,
    airport_id    INT          NOT NULL,        -- natural key dari OLTP
    iata_code     CHAR(3),
    airport_name  VARCHAR(150) NOT NULL,
    country_code  CHAR(2)      NOT NULL,
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NOT NULL DEFAULT DATE '9999-12-31',
    is_current    BOOLEAN      NOT NULL DEFAULT TRUE,
    version       INT          NOT NULL DEFAULT 1,
    CONSTRAINT uq_dim_airport_version UNIQUE (airport_id, version),
    CONSTRAINT chk_dim_airport_range  CHECK (valid_to >= valid_from)
);

COMMENT ON TABLE  dim_airport IS 'Dimensi bandara; SCD2 pada airport_name, SCD0 pada iata_code';
COMMENT ON COLUMN dim_airport.iata_code IS 'Kode IATA; atribut tetap (SCD0)';

CREATE INDEX idx_dim_airport_nk    ON dim_airport (airport_id, is_current);
CREATE INDEX idx_dim_airport_range ON dim_airport (airport_id, valid_from, valid_to);
CREATE INDEX idx_dim_airport_iata  ON dim_airport (iata_code);

CREATE TABLE dim_passenger (
    passenger_key  SERIAL PRIMARY KEY,
    passenger_id   VARCHAR(10) NOT NULL UNIQUE,
    first_name     VARCHAR(50) NOT NULL,
    last_name      VARCHAR(50) NOT NULL,
    gender         VARCHAR(10) NOT NULL,
    age            SMALLINT    NOT NULL,
    age_band       VARCHAR(20) NOT NULL,
    nationality    VARCHAR(60) NOT NULL
);

COMMENT ON TABLE dim_passenger IS 'Dimensi penumpang; atribut profil pada saat record dibuat';

CREATE TABLE dim_pilot (
    pilot_key   SERIAL PRIMARY KEY,
    pilot_id    INT          NOT NULL UNIQUE,
    pilot_name  VARCHAR(100) NOT NULL
);

COMMENT ON TABLE dim_pilot IS 'Dimensi pilot';

CREATE TABLE dim_flight_status (
    status_key    SERIAL PRIMARY KEY,
    status_code   VARCHAR(5)  NOT NULL UNIQUE,
    status_name   VARCHAR(20) NOT NULL,
    is_operated   SMALLINT    NOT NULL CHECK (is_operated  IN (0,1)),
    is_cancelled  SMALLINT    NOT NULL CHECK (is_cancelled IN (0,1)),
    is_on_time    SMALLINT    NOT NULL CHECK (is_on_time   IN (0,1)),
    is_delayed    SMALLINT    NOT NULL CHECK (is_delayed   IN (0,1))
);

COMMENT ON TABLE dim_flight_status IS 'Dimensi status: On Time, Delayed, Cancelled';

-- ----------------------------------------------------------------------------
-- 2. FACT TABLES
-- ----------------------------------------------------------------------------

-- FACT 1: TRANSACTIONAL
-- Grain: satu baris untuk setiap passenger flight record.
CREATE TABLE fact_flight (
    flight_fact_key  BIGSERIAL PRIMARY KEY,
    flight_id        BIGINT        NOT NULL UNIQUE,     -- degenerate dimension
    flight_date_key  INT           NOT NULL REFERENCES dim_date(date_key),
    airport_key      INT           NOT NULL REFERENCES dim_airport(airport_key),
    country_key      INT           NOT NULL REFERENCES dim_country(country_key),
    passenger_key    INT           NOT NULL REFERENCES dim_passenger(passenger_key),
    pilot_key        INT           NOT NULL REFERENCES dim_pilot(pilot_key),
    status_key       INT           NOT NULL REFERENCES dim_flight_status(status_key),
    -- measures
    flight_count     SMALLINT      NOT NULL DEFAULT 1,
    passenger_count  SMALLINT      NOT NULL DEFAULT 1,
    -- flags untuk KPI
    is_operated      SMALLINT      NOT NULL CHECK (is_operated  IN (0,1)),
    is_on_time       SMALLINT      NOT NULL CHECK (is_on_time   IN (0,1)),
    is_delayed       SMALLINT      NOT NULL CHECK (is_delayed   IN (0,1)),
    is_cancelled     SMALLINT      NOT NULL CHECK (is_cancelled IN (0,1))
);

COMMENT ON TABLE fact_flight IS
    'Transactional fact: grain = 1 passenger flight record (1 baris CSV)';

CREATE INDEX idx_fact_flight_date         ON fact_flight (flight_date_key);
CREATE INDEX idx_fact_flight_date_country ON fact_flight (flight_date_key, country_key);
CREATE INDEX idx_fact_flight_airport      ON fact_flight (airport_key);
CREATE INDEX idx_fact_flight_country   ON fact_flight (country_key);
CREATE INDEX idx_fact_flight_status    ON fact_flight (status_key);
CREATE INDEX idx_fact_flight_passenger ON fact_flight (passenger_key);

-- FACT 2: PERIODIC SNAPSHOT (harian per negara)
-- Grain: satu baris per negara per hari, termasuk hari tanpa penerbangan.
CREATE TABLE fact_daily_country_snapshot (
    snapshot_fact_key   BIGSERIAL PRIMARY KEY,
    snapshot_date_key   INT      NOT NULL REFERENCES dim_date(date_key),
    country_key         INT      NOT NULL REFERENCES dim_country(country_key),
    flight_count        INT      NOT NULL DEFAULT 0,
    passenger_count     INT      NOT NULL DEFAULT 0,
    operated_flights    INT      NOT NULL DEFAULT 0,
    on_time_flights     INT      NOT NULL DEFAULT 0,
    delayed_flights     INT      NOT NULL DEFAULT 0,
    cancelled_flights   INT      NOT NULL DEFAULT 0,
    on_time_rate        NUMERIC(6,4) NOT NULL DEFAULT 0,
    cancellation_rate   NUMERIC(6,4) NOT NULL DEFAULT 0,
    CONSTRAINT uq_daily_country_grain UNIQUE (snapshot_date_key, country_key)
);

COMMENT ON TABLE fact_daily_country_snapshot IS
    'Periodic snapshot: grain = 1 negara x 1 hari, termasuk hari tanpa flight (zero rows)';

CREATE INDEX idx_snapshot_date    ON fact_daily_country_snapshot (snapshot_date_key);
CREATE INDEX idx_snapshot_country ON fact_daily_country_snapshot (country_key);

-- ----------------------------------------------------------------------------
-- 3. HELPER VIEWS
-- ----------------------------------------------------------------------------

CREATE VIEW v_flight_detail AS
SELECT f.flight_id,
       d.full_date              AS flight_date,
       a.iata_code,
       a.airport_name,
       c.country_name,
       c.continent_name,
       p.passenger_id,
       p.gender,
       p.age,
       p.age_band,
       p.nationality,
       pl.pilot_name,
       st.status_code,
       st.status_name
FROM fact_flight f
JOIN dim_date          d  ON d.date_key = f.flight_date_key
JOIN dim_airport       a  ON a.airport_key = f.airport_key
JOIN dim_country       c  ON c.country_key = f.country_key
JOIN dim_passenger     p  ON p.passenger_key = f.passenger_key
JOIN dim_pilot         pl ON pl.pilot_key = f.pilot_key
JOIN dim_flight_status st ON st.status_key = f.status_key;

COMMENT ON VIEW v_flight_detail IS 'Join lengkap untuk eksplorasi/validasi';

CREATE VIEW v_monthly_kpi AS
SELECT d.year,
       d.month_number,
       d.month_year,
       COUNT(*)                                                          AS total_flights,
       SUM(f.is_operated)                                                AS operated_flights,
       SUM(f.is_on_time)                                                 AS on_time_flights,
       SUM(f.is_delayed)                                                 AS delayed_flights,
       SUM(f.is_cancelled)                                               AS cancelled_flights,
       ROUND(100.0 * SUM(f.is_on_time)  / NULLIF(SUM(f.is_operated),0), 2) AS on_time_rate_pct,
       ROUND(100.0 * SUM(f.is_delayed)  / NULLIF(SUM(f.is_operated),0), 2) AS delay_rate_pct,
       ROUND(100.0 * SUM(f.is_cancelled) / NULLIF(COUNT(*),0), 2)         AS cancellation_rate_pct
FROM fact_flight f
JOIN dim_date d ON d.date_key = f.flight_date_key
GROUP BY d.year, d.month_number, d.month_year;

COMMENT ON VIEW v_monthly_kpi IS 'KPI bulanan untuk validasi dashboard';

CREATE VIEW v_airport_kpi AS
SELECT a.airport_name,
       a.iata_code,
       c.country_name,
       COUNT(*)                                                          AS total_flights,
       SUM(f.is_on_time)                                                 AS on_time_flights,
       SUM(f.is_cancelled)                                               AS cancelled_flights,
       ROUND(100.0 * SUM(f.is_on_time) / NULLIF(SUM(f.is_operated),0), 2) AS on_time_rate_pct,
       ROUND(100.0 * SUM(f.is_cancelled) / NULLIF(COUNT(*),0), 2)        AS cancellation_rate_pct
FROM fact_flight f
JOIN dim_airport a ON a.airport_key = f.airport_key
JOIN dim_country c ON c.country_key = f.country_key
GROUP BY a.airport_name, a.iata_code, c.country_name;

COMMENT ON VIEW v_airport_kpi IS 'KPI per bandara untuk validasi';
