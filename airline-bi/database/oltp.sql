-- ============================================================================
--  Nusantara Air - OLTP Database (PostgreSQL)
--  Studi kasus : analisis kinerja operasional penerbangan
--  Sumber data : "Airline Dataset Updated - v2.csv" (98.619 baris)
--  File        : database/oltp.sql
--  Cara pakai  : psql -U postgres -d airline -f database/oltp.sql
--
--  Model mengikuti grain dataset: 1 baris = 1 record penerbangan penumpang
--  (passenger flight record). Dataset tidak memuat jadwal/actual time,
--  aircraft, kapasitas, atau durasi delay, sehingga atribut tersebut tidak
--  dipaksakan ke dalam model.
-- ============================================================================

DROP SCHEMA IF EXISTS oltp CASCADE;
CREATE SCHEMA oltp;
SET search_path TO oltp, public;

-- ----------------------------------------------------------------------------
-- 1. MASTER DATA
-- ----------------------------------------------------------------------------

CREATE TABLE countries (
    country_code    CHAR(2)     PRIMARY KEY,
    country_name    VARCHAR(100) NOT NULL,
    continent_code  CHAR(3)     NOT NULL,
    continent_name  VARCHAR(30) NOT NULL
);

COMMENT ON TABLE countries IS 'Negara asal bandara + benua';

CREATE TABLE airports (
    airport_id    SERIAL PRIMARY KEY,
    iata_code     CHAR(3),
    airport_name  VARCHAR(150) NOT NULL,
    country_code  CHAR(2)      NOT NULL REFERENCES countries(country_code),
    CONSTRAINT uq_airport_name_country UNIQUE (airport_name, country_code)
);

COMMENT ON TABLE  airports IS 'Bandara keberangkatan; natural key = nama bandara + negara';
COMMENT ON COLUMN airports.iata_code IS 'Kode IATA; diambil dari kolom Arrival Airport pada dataset (kode bandara asal)';

CREATE INDEX idx_airports_iata    ON airports (iata_code);
CREATE INDEX idx_airports_country ON airports (country_code);

CREATE TABLE passengers (
    passenger_id  VARCHAR(10) PRIMARY KEY,
    first_name    VARCHAR(50) NOT NULL,
    last_name     VARCHAR(50) NOT NULL,
    gender        VARCHAR(10) NOT NULL CHECK (gender IN ('Male','Female')),
    age           SMALLINT    NOT NULL CHECK (age BETWEEN 0 AND 120),
    nationality   VARCHAR(60) NOT NULL
);

COMMENT ON TABLE passengers IS 'Profil penumpang pada setiap record penerbangan';

CREATE TABLE pilots (
    pilot_id    SERIAL PRIMARY KEY,
    pilot_name  VARCHAR(100) NOT NULL
);

COMMENT ON TABLE pilots IS 'Nama pilot pada setiap record penerbangan';

CREATE TABLE flight_statuses (
    status_id     SERIAL PRIMARY KEY,
    status_code   VARCHAR(5)  NOT NULL UNIQUE,
    status_name   VARCHAR(20) NOT NULL,
    is_operated   SMALLINT    NOT NULL CHECK (is_operated  IN (0,1)),
    is_cancelled  SMALLINT    NOT NULL CHECK (is_cancelled IN (0,1))
);

COMMENT ON TABLE flight_statuses IS 'Status penerbangan: On Time, Delayed, Cancelled';

-- ----------------------------------------------------------------------------
-- 2. TRANSAKSI
-- ----------------------------------------------------------------------------

-- Satu baris = satu record penerbangan penumpang.
CREATE TABLE flights (
    flight_id              BIGSERIAL PRIMARY KEY,
    flight_date            DATE        NOT NULL,
    origin_airport_id      INT         NOT NULL REFERENCES airports(airport_id),
    pilot_id               INT         NOT NULL REFERENCES pilots(pilot_id),
    passenger_id           VARCHAR(10) NOT NULL REFERENCES passengers(passenger_id),
    status_id              INT         NOT NULL REFERENCES flight_statuses(status_id),
    recorded_arrival_code  CHAR(3),               -- nilai mentah kolom Arrival Airport
    created_at             TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  flights IS 'Grain = 1 record penerbangan penumpang (satu baris CSV)';
COMMENT ON COLUMN flights.recorded_arrival_code IS
    'Kode bandara pada kolom Arrival Airport; pada 74.063 baris sama dengan bandara asal (data quality note)';

CREATE INDEX idx_flights_date      ON flights (flight_date);
CREATE INDEX idx_flights_airport   ON flights (origin_airport_id);
CREATE INDEX idx_flights_status    ON flights (status_id);
CREATE INDEX idx_flights_pilot     ON flights (pilot_id);
CREATE INDEX idx_flights_passenger ON flights (passenger_id);

-- View bantu untuk eksplorasi dan validasi.
CREATE VIEW v_flight_record AS
SELECT f.flight_id,
       f.flight_date,
       a.iata_code,
       a.airport_name,
       a.country_code,
       c.country_name,
       c.continent_code,
       c.continent_name,
       p.passenger_id,
       p.first_name,
       p.last_name,
       p.gender,
       p.age,
       p.nationality,
       pl.pilot_name,
       s.status_code,
       s.status_name,
       f.recorded_arrival_code
FROM flights f
JOIN airports        a  ON a.airport_id = f.origin_airport_id
JOIN countries       c  ON c.country_code = a.country_code
JOIN passengers      p  ON p.passenger_id = f.passenger_id
JOIN pilots          pl ON pl.pilot_id = f.pilot_id
JOIN flight_statuses s  ON s.status_id = f.status_id;

COMMENT ON VIEW v_flight_record IS 'Join lengkap record penerbangan untuk eksplorasi/validasi';

-- ----------------------------------------------------------------------------
-- 3. DATA REFERENSI + CONTOH
-- ----------------------------------------------------------------------------

INSERT INTO flight_statuses (status_id, status_code, status_name, is_operated, is_cancelled) VALUES
    (1, 'ONT', 'On Time',   1, 0),
    (2, 'DLY', 'Delayed',   1, 0),
    (3, 'CNL', 'Cancelled', 0, 1);

INSERT INTO countries (country_code, country_name, continent_code, continent_name) VALUES
    ('ID', 'Indonesia',      'AS',  'Asia'),
    ('SG', 'Singapore',      'AS',  'Asia'),
    ('MY', 'Malaysia',       'AS',  'Asia');

INSERT INTO airports (airport_id, iata_code, airport_name, country_code) VALUES
    (1, 'CGK', 'Soekarno-Hatta International Airport', 'ID'),
    (2, 'DPS', 'Ngurah Rai (Bali) International Airport', 'ID'),
    (3, 'SUB', 'Juanda International Airport', 'ID');

INSERT INTO passengers (passenger_id, first_name, last_name, gender, age, nationality) VALUES
    ('P00001', 'Andi',  'Pratama', 'Male',   34, 'Indonesia'),
    ('P00002', 'Siti',  'Aminah',  'Female', 29, 'Indonesia'),
    ('P00003', 'James', 'Wong',    'Male',   41, 'Singapore');

INSERT INTO pilots (pilot_id, pilot_name) VALUES
    (1, 'Capt. Rizky Ramadhan'),
    (2, 'Capt. Dewi Lestari'),
    (3, 'Capt. Agus Setiawan');

INSERT INTO flights (flight_id, flight_date, origin_airport_id, pilot_id, passenger_id, status_id, recorded_arrival_code) VALUES
    (1, DATE '2022-01-03', 1, 1, 'P00001', 1, 'CGK'),
    (2, DATE '2022-01-03', 2, 2, 'P00002', 2, 'DPS'),
    (3, DATE '2022-01-04', 3, 3, 'P00003', 3, 'SUB'),
    (4, DATE '2022-02-11', 1, 2, 'P00002', 1, 'CGK'),
    (5, DATE '2022-02-12', 2, 3, 'P00003', 1, 'DPS'),
    (6, DATE '2022-03-05', 3, 1, 'P00001', 2, 'SUB');

SELECT setval(pg_get_serial_sequence('airports', 'airport_id'), (SELECT MAX(airport_id) FROM airports));
SELECT setval(pg_get_serial_sequence('pilots', 'pilot_id'),     (SELECT MAX(pilot_id) FROM pilots));
SELECT setval(pg_get_serial_sequence('flights', 'flight_id'),   (SELECT MAX(flight_id) FROM flights));

-- ----------------------------------------------------------------------------
-- 4. RINGKASAN
-- ----------------------------------------------------------------------------
SELECT 'countries'       AS tabel, COUNT(*) AS baris FROM countries
UNION ALL SELECT 'airports',        COUNT(*) FROM airports
UNION ALL SELECT 'passengers',      COUNT(*) FROM passengers
UNION ALL SELECT 'pilots',          COUNT(*) FROM pilots
UNION ALL SELECT 'flight_statuses', COUNT(*) FROM flight_statuses
UNION ALL SELECT 'flights',         COUNT(*) FROM flights;
