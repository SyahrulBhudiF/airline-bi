-- ============================================================================
--  SCD DEMO - perubahan sumber untuk menguji SCD Type 1 dan Type 2
--  File     : database/scd_demo.sql
--  Cara pakai: psql -U postgres -d airline -f database/scd_demo.sql
--
--  Urutan demo:
--    1. Jalankan ETL awal dengan SCD_AS_OF_DATE = 2022-01-01.
--    2. Jalankan script ini (perubahan efektif 1 Juli 2022).
--    3. Jalankan ETL lagi dengan SCD_AS_OF_DATE = 2022-07-01.
--
--  SCD Type 1 (overwrite, tanpa histori):
--    Turkey -> Türkiye  (koreksi nama resmi negara)
--
--  SCD Type 2 (versi baru, histori disimpan):
--    - Soekarno-Hatta International Airport -> ... (CGK)
--    - Ngurah Rai (Bali) International Airport -> I Gusti Ngurah Rai International Airport
--    - Juanda International Airport -> Juanda International Airport Surabaya
--    - Adi Sutjipto International Airport -> Adisutjipto International Airport
-- ============================================================================

SET search_path TO oltp, public;

-- SCD Type 1: koreksi nama negara. Nilai lama ditimpa, tidak ada versi baru.
UPDATE countries
SET    country_name = 'Türkiye'
WHERE  country_code = 'TR';

-- SCD Type 2: perubahan nama bandara. ETL akan menutup versi lama dan
-- membuat versi baru dengan valid_from = 2022-07-01.
UPDATE airports
SET    airport_name = 'Soekarno-Hatta International Airport (CGK)'
WHERE  airport_name = 'Soekarno-Hatta International Airport'
  AND  country_code = 'ID';

UPDATE airports
SET    airport_name = 'I Gusti Ngurah Rai International Airport'
WHERE  airport_name = 'Ngurah Rai (Bali) International Airport'
  AND  country_code = 'ID';

UPDATE airports
SET    airport_name = 'Juanda International Airport Surabaya'
WHERE  airport_name = 'Juanda International Airport'
  AND  country_code = 'ID';

UPDATE airports
SET    airport_name = 'Adisutjipto International Airport'
WHERE  airport_name = 'Adi Sutjipto International Airport'
  AND  country_code = 'ID';

-- Ringkasan perubahan.
SELECT country_code, country_name FROM countries WHERE country_code = 'TR';
SELECT iata_code, airport_name FROM airports
WHERE iata_code IN ('CGK', 'DPS', 'SUB', 'JOG')
  AND country_code = 'ID'
ORDER BY iata_code;
