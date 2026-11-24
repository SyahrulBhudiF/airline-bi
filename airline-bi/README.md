# Nusantara Air — Business Intelligence Project

Proyek BI end-to-end untuk analisis kinerja operasional penerbangan:
**PostgreSQL (OLTP + data warehouse) → Pentaho Data Integration (ETL) → Power BI (dashboard)**.

Sumber data: `data/raw/Airline-Dataset-Updated-v2.csv.zip`
(98.619 baris passenger flight record, periode 2022).

> **Baca bagian [Catatan Data](#9-catatan-data-dan-keterbatasan) sebelum presentasi.**
> Dataset tidak memiliki jam keberangkatan/kedatangan, aircraft, kapasitas kursi,
> durasi delay, atau alasan delay. Karena itu KPI disesuaikan dengan data yang ada
> (status, volume, bandara/negara, profil penumpang, snapshot harian). Penjelasan
> lengkap ada di bagian 9.

---

## Daftar Isi

1. [Struktur Folder](#1-struktur-folder)
2. [Prasyarat](#2-prasyarat)
3. [Setup Database dan Load Data](#3-setup-database-dan-load-data)
4. [Tutorial Pentaho: Menjalankan ETL](#4-tutorial-pentaho-menjalankan-etl)
5. [Demo SCD Type 1 dan Type 2](#5-demo-scd-type-1-dan-type-2)
6. [Tutorial Power BI: Merakit Dashboard](#6-tutorial-power-bi-merakit-dashboard)
7. [Validasi Hasil](#7-validasi-hasil)
8. [Troubleshooting](#8-troubleshooting)
9. [Catatan Data dan Keterbatasan](#9-catatan-data-dan-keterbatasan)
10. [Status Pengujian](#10-status-pengujian)

---

## 1. Struktur Folder

```text
airline-bi/
├── database/
│   ├── oltp.sql              # schema OLTP + data contoh
│   ├── warehouse.sql         # star schema (dimension + 2 fact)
│   ├── scd_demo.sql          # perubahan sumber untuk demo SCD 1 & 2
│   └── validation.sql        # query validasi + KPI
├── data/
│   ├── load_data.py          # load CSV ke schema OLTP
│   ├── requirements.txt      # pandas + psycopg2-binary
│   ├── data-quality-report.txt
│   └── raw/
│       └── Airline-Dataset-Updated-v2.csv.zip
├── pentaho/
│   ├── transformations/      # 9 file .ktr
│   │   ├── 01_load_dim_date.ktr
│   │   ├── 02_load_dim_country.ktr
│   │   ├── 03_load_dim_pilot.ktr
│   │   ├── 04_load_dim_passenger.ktr
│   │   ├── 05_load_dim_flight_status.ktr
│   │   ├── 06_close_airport_versions.ktr
│   │   ├── 07_insert_airport_versions.ktr
│   │   ├── 08_load_fact_flight.ktr
│   │   └── 09_load_fact_daily_country_snapshot.ktr
│   └── jobs/
│       └── load_warehouse.kjb
├── powerbi/
│   ├── measures.dax          # semua DAX measure
│   └── dashboard-guide.md    # panduan detail visual & layout
├── docs/
│   ├── oltp-erd.png
│   ├── star-schema.png
│   ├── etl-flow.png
│   └── dashboard-layout.png
└── README.md
```

---

## 2. Prasyarat

| Komponen | Versi yang diuji | Catatan |
|---|---|---|
| PostgreSQL | 15.20 | Schema `oltp` dan `dw` |
| Python | 3.11 | `pandas`, `psycopg2-binary` |
| Pentaho Data Integration | 7.0.0.0-25 | Jalankan dengan **Java 8**; PDI 9/10 bisa membuka file, tetapi sesuaikan Java-nya |
| Power BI Desktop | Windows | Manual, tidak tersedia di lingkungan Linux |
| Driver PostgreSQL | `postgresql-42.7.4.jar` | Untuk PDI; driver bawaan PDI 7 (9.3) tidak mendukung SCRAM |

> PDI 7 membutuhkan Java 8. Jika memakai PDI 9/10, gunakan Java 11/17 dan buka
> setiap `.ktr` di Spoon lalu simpan ulang agar formatnya sesuai versi tersebut.

---

## 3. Setup Database dan Load Data

> Semua perintah di bagian ini dijalankan dari folder `airline-bi/`.
> Jika database `airline` sudah ada, lewati langkah 3.1 atau drop dulu database
> tersebut (data lama akan hilang).

### 3.1 Buat database

```bash
sudo -u postgres psql -c "CREATE DATABASE airline;"
```

### 3.2 Buat schema OLTP

```bash
psql -U postgres -d airline -f database/oltp.sql
```

Script ini membuat schema `oltp`, tabel, relasi, index, dan data contoh kecil.
Output akhirnya menampilkan jumlah baris per tabel.

![ERD OLTP](docs/oltp-erd.png)

### 3.3 Install dependency Python

```bash
python3 -m pip install -r data/requirements.txt
```

### 3.4 Load dataset CSV ke OLTP

```bash
python3 data/load_data.py \
  --dsn "postgresql://postgres:postgres@localhost:5432/airline"
```

Yang dilakukan loader:

- membaca zip CSV (`data/raw/Airline-Dataset-Updated-v2.csv.zip`);
- menormalkan dua format tanggal (`m/d/Y` dan `d-m-Y`);
- memetakan nama bandara + kode negara menjadi `airport_id`;
- mengambil kode IATA dari kolom `Arrival Airport` (lihat catatan data);
- mengisi `countries`, `airports`, `passengers`, `pilots`, `flights`;
- menulis `data/data-quality-report.txt`.

Output yang diharapkan:

```text
Cleaned rows: 98,619
Loaded 98,619 flights, 98,619 passengers, 9,107 airports, 98,605 pilots.
```

### 3.5 Buat data warehouse

```bash
psql -U postgres -d airline -f database/warehouse.sql
```

Script ini membuat schema `dw`:

- `dim_date`, `dim_country`, `dim_airport`, `dim_passenger`, `dim_pilot`, `dim_flight_status`;
- `fact_flight` (transactional);
- `fact_daily_country_snapshot` (periodic snapshot);
- view validasi `v_flight_detail`, `v_monthly_kpi`, `v_airport_kpi`.

> Jangan jalankan ETL sebelum `warehouse.sql` selesai. Tabel dimensi dan fact
> harus sudah ada.

![Star schema](docs/star-schema.png)

---

## 4. Tutorial Pentaho: Menjalankan ETL

### 4.1 Install dan buka PDI

1. Download **Pentaho Data Integration Community Edition** (versi 7+).
2. Extract, lalu jalankan:
   - Linux: `spoon.sh`
   - Windows: `Spoon.bat`
3. Pastikan Java yang dipakai sesuai:
   - PDI 7 → Java 8.
   - PDI 9/10 → Java 11/17.

Jika muncul error `Unrecognized VM option 'MaxPermSize=256m'`, berarti PDI 7
dijalankan dengan Java 17. Ganti ke Java 8, atau hapus opsi `-XX:MaxPermSize`
dari `spoon.sh`/`pan.sh`/`kitchen.sh` (kurang disarankan).

### 4.2 Buat dua koneksi database

Di Spoon: **View → Database Connections → New**.

**Koneksi 1 — OLTP**

| Field | Nilai |
|---|---|
| Connection name | `OLTP` |
| Connection type | PostgreSQL |
| Host name | `localhost` |
| Port | `5432` |
| Database name | `airline` |
| Username | `postgres` |
| Password | `postgres` |

Klik **Test**. Jika berhasil, klik **OK**.

**Koneksi 2 — DW**

Sama seperti di atas, tetapi connection name harus **`DW`**.

> Nama koneksi harus persis `OLTP` dan `DW` karena semua `.ktr` memanggil nama
> tersebut. Keduanya menunjuk database yang sama; yang berbeda hanya schema
> (`oltp.*` untuk sumber, `dw.*` untuk target).
>
> Jika host/user/password berbeda, edit koneksi di **setiap** `.ktr` yang
> membutuhkannya (Spoon menyimpan koneksi di dalam file, bukan di satu tempat).

### 4.3 Buka job utama

1. **File → Open → `pentaho/jobs/load_warehouse.kjb`**.
2. Job berisi urutan:
   ```text
   Start
    → 01 load dim date
    → 02 load dim country
    → 03 load dim pilot
    → 04 load dim passenger
    → 05 load dim flight status
    → 06 close airport versions   (SCD Type 2)
    → 07 insert airport versions  (SCD Type 2)
    → 08 load fact flight
    → 09 load fact daily country snapshot
   ```
3. Pastikan path transformation di setiap entry mengarah ke
   `../transformations/...` (relatif terhadap job). Jika folder dipindah,
   path ini tetap bekerja selama struktur folder tidak diubah.

### 4.4 Set parameter SCD

Job memiliki parameter:

```text
SCD_AS_OF_DATE = 2022-01-01
```

Untuk load awal, nilai default ini sudah benar.

Cara mengubah di Spoon:

1. Klik kanan canvas job → **Properties** (atau **Edit → Job properties**).
2. Buka tab **Parameters**.
3. Ubah `SCD_AS_OF_DATE` bila perlu.
4. Klik **OK**.

Jika memakai command line, parameter bisa diberikan langsung (lihat 4.6).

### 4.5 Jalankan ETL pertama

1. Tekan **F9** atau **Action → Run**.
2. Di dialog run, klik **Run**.
3. Pantau log di bagian bawah Spoon.

Urutan hasil yang diharapkan:

| Transformation | Baris | Keterangan |
|---|---:|---|
| 01 dim_date | 365 | 1 Jan – 31 Des 2022 |
| 02 dim_country | 235 | |
| 03 dim_pilot | 98.605 | |
| 04 dim_passenger | 98.619 | |
| 05 dim_flight_status | 3 | On Time, Delayed, Cancelled |
| 06 close airport versions | 0 | Belum ada perubahan nama |
| 07 insert airport versions | 9.107 | Versi 1 untuk semua bandara |
| 08 fact_flight | 98.619 | |
| 09 snapshot | 85.775 | 235 negara × 365 hari |

Setelah selesai, cek di pgAdmin/psql:

```sql
SELECT COUNT(*) FROM dw.fact_flight;                     -- 98.619
SELECT COUNT(*) FROM dw.fact_daily_country_snapshot;     -- 85.775
SELECT COUNT(*) FROM dw.dim_airport;                     -- 9.107
```

### 4.6 Jalankan ETL lewat command line (opsional)

Linux/macOS:

```bash
export JAVA_HOME=/path/to/java8
cd /path/to/pdi/data-integration

./kitchen.sh \
  -file=/path/to/airline-bi/pentaho/jobs/load_warehouse.kjb \
  -param:SCD_AS_OF_DATE=2022-01-01
```

Windows:

```bat
Kitchen.bat /file:"C:\path\to\airline-bi\pentaho\jobs\load_warehouse.kjb" /param:SCD_AS_OF_DATE=2022-01-01
```

Untuk load incremental (setelah demo SCD):

```bash
./kitchen.sh \
  -file=/path/to/airline-bi/pentaho/jobs/load_warehouse.kjb \
  -param:SCD_AS_OF_DATE=2022-07-01
```

### 4.7 Cara ETL bekerja (untuk presentasi)

- **Dimension load** memakai step **Insert/Update**:
  - `dim_date`, `dim_flight_status`: data referensi.
  - `dim_country`, `dim_pilot`, `dim_passenger`: update atribut (SCD Type 1).
- **`dim_airport` memakai SCD Type 2 dua langkah**:
  - `06_close_airport_versions.ktr` menutup versi lama:
    `valid_to = SCD_AS_OF_DATE - 1`, `is_current = false`.
  - `07_insert_airport_versions.ktr` memasukkan versi baru:
    `version = max(version) + 1`, `valid_from = SCD_AS_OF_DATE`,
    `valid_to = 9999-12-31`, `is_current = true`.
  - Urutan ini penting: close harus selesai sebelum insert.
- **Surrogate key lookup** di fact dilakukan lewat `JOIN` di SQL source
  (`08_load_fact_flight.ktr`), bukan lookup baris-per-baris. Ini lebih cepat
  untuk 98 ribu baris dan tetap merupakan proses lookup natural key → surrogate key.
- **Fact load** memakai **Table Output** dengan `truncate = Y`, sehingga setiap
  run faktanya di-load ulang (idempotent), sementara dimensi memakai Insert/Update.
- **Snapshot fact** membentuk cross join `dim_date × dim_country`, lalu
  `LEFT JOIN fact_flight`; hari tanpa flight tetap muncul dengan nilai 0.

![Alur ETL](docs/etl-flow.png)

---

## 5. Demo SCD Type 1 dan Type 2

Demo ini membuktikan bahwa dimensi menyimpan histori dengan benar. Jalankan
**setelah ETL pertama selesai**.

### 5.1 Ubah data sumber

```bash
psql -U postgres -d airline -f database/scd_demo.sql
```

Perubahan yang dilakukan:

| Tipe | Objek | Sebelum | Sesudah |
|---|---|---|---|
| SCD 1 | Negara TR | `Turkey` | `Türkiye` |
| SCD 2 | Bandara CGK | `Soekarno-Hatta International Airport` | `Soekarno-Hatta International Airport (CGK)` |
| SCD 2 | Bandara DPS | `Ngurah Rai (Bali) International Airport` | `I Gusti Ngurah Rai International Airport` |
| SCD 2 | Bandara SUB | `Juanda International Airport` | `Juanda International Airport Surabaya` |
| SCD 2 | Bandara JOG | `Adi Sutjipto International Airport` | `Adisutjipto International Airport` |

### 5.2 Jalankan ETL kedua

Ubah parameter `SCD_AS_OF_DATE` menjadi `2022-07-01`, lalu jalankan job lagi.

Atau lewat command line:

```bash
./kitchen.sh \
  -file=/path/to/airline-bi/pentaho/jobs/load_warehouse.kjb \
  -param:SCD_AS_OF_DATE=2022-07-01
```

### 5.3 Verifikasi hasil SCD

**SCD Type 2 — versi bandara:**

```sql
SELECT iata_code, airport_name, valid_from, valid_to, is_current, version
FROM dw.dim_airport
WHERE iata_code IN ('CGK', 'DPS', 'SUB', 'JOG')
  AND country_code = 'ID'
ORDER BY iata_code, version;
```

Hasil yang diharapkan: 8 baris (4 bandara × 2 versi). Contoh CGK:

| iata_code | airport_name | valid_from | valid_to | is_current | version |
|---|---|---|---|---|---|
| CGK | Soekarno-Hatta International Airport | 2022-01-01 | 2022-06-30 | false | 1 |
| CGK | Soekarno-Hatta International Airport (CGK) | 2022-07-01 | 9999-12-31 | true | 2 |

**Historical fact memakai versi yang benar:**

```sql
SELECT d.full_date, a.airport_name, a.version, COUNT(*) AS flights
FROM dw.fact_flight f
JOIN dw.dim_airport a ON a.airport_key = f.airport_key
JOIN dw.dim_date d ON d.date_key = f.flight_date_key
WHERE a.iata_code = 'CGK'
  AND a.country_code = 'ID'
GROUP BY 1, 2, 3
ORDER BY 1;
```

Flight sebelum 1 Juli 2022 memakai versi 1 (nama lama); flight setelahnya
memakai versi 2 (nama baru).

**SCD Type 1 — nama negara:**

```sql
SELECT c.country_code, c.country_name, COUNT(*) AS flights
FROM dw.fact_flight f
JOIN dw.dim_country c USING (country_key)
WHERE c.country_code = 'TR'
GROUP BY 1, 2;
```

Hasil: `TR | Türkiye | 704`. Tidak ada baris versi baru; nilai lama ditimpa
dan seluruh histori langsung menampilkan nama baru.

**Tidak ada flight yang memakai versi salah:**

```sql
SELECT COUNT(*) AS bad_version
FROM dw.fact_flight f
JOIN dw.dim_airport a USING (airport_key)
JOIN dw.dim_date d ON d.date_key = f.flight_date_key
WHERE d.full_date NOT BETWEEN a.valid_from AND a.valid_to;
```

Hasil: `0`.

---

## 6. Tutorial Power BI: Merakit Dashboard

Power BI Desktop tidak tersedia di Linux, jadi file `.pbix` tidak disertakan.
Ikuti langkah berikut untuk merakit dashboard dari data warehouse yang sudah ada.

### 6.1 Koneksi

1. Buka **Power BI Desktop → Get Data → More → Database → PostgreSQL database**.
2. Isi:
   - **Server**: `localhost:5432`
   - **Database**: `airline`
   - **Data Connectivity mode**: `Import`
3. Klik **OK**, masukkan user `postgres` / password `postgres`.
4. Pilih tabel:
   - `dw.fact_flight`
   - `dw.fact_daily_country_snapshot`
   - `dw.dim_date`
   - `dw.dim_airport`
   - `dw.dim_country`
   - `dw.dim_passenger`
   - `dw.dim_pilot`
   - `dw.dim_flight_status`
5. Klik **Load**.

Jika provider PostgreSQL belum ada, install **Npgsql** (mis. Npgsql 4.1+), lalu
ulangi langkah di atas.

### 6.2 Relasi model

Buka **Model view**, buat relasi **one-to-many** berikut:

| Dari (1) | Ke (*) | Kolom |
|---|---|---|
| `dim_date` | `fact_flight` | `date_key` → `flight_date_key` |
| `dim_date` | `fact_daily_country_snapshot` | `date_key` → `snapshot_date_key` |
| `dim_airport` | `fact_flight` | `airport_key` → `airport_key` |
| `dim_country` | `fact_flight` | `country_key` → `country_key` |
| `dim_country` | `fact_daily_country_snapshot` | `country_key` → `country_key` |
| `dim_passenger` | `fact_flight` | `passenger_key` → `passenger_key` |
| `dim_pilot` | `fact_flight` | `pilot_key` → `pilot_key` |
| `dim_flight_status` | `fact_flight` | `status_key` → `status_key` |

Catatan:

- Jangan membuat relasi `dim_airport` → `dim_country`; `dim_airport` hanya
  menyimpan `country_code`, bukan `country_key`.
- Tandai `dim_date` sebagai **Mark as date table** menggunakan `full_date`.
- Urutkan `dim_date[month_name]` berdasarkan `month_number`.
- Sembunyikan kolom teknis (`*_key`, `valid_from`, `valid_to`, `version`)
  dari **Report view**.

### 6.3 Measure DAX

1. **Home → Enter Data**, buat tabel `_Measures` dengan satu kolom
   `Placeholder`, klik **Load**, lalu sembunyikan kolomnya.
2. Buka `powerbi/measures.dax`, lalu buat setiap measure di tabel `_Measures`
   melalui **Modeling → New Measure**.
3. Format angka:
   - Counts: **Whole Number**, pemisah ribuan.
   - Rates: **Percentage**, 1 desimal.
   - Age: **Decimal**, 1 desimal.

Measure inti:

```dax
Total Flights = COUNTROWS ( fact_flight )

On-Time Rate =
DIVIDE (
    CALCULATE ( [Total Flights], fact_flight[is_on_time] = 1 ),
    CALCULATE ( [Total Flights], fact_flight[is_operated] = 1 )
)

Delay Rate =
DIVIDE (
    CALCULATE ( [Total Flights], fact_flight[is_delayed] = 1 ),
    CALCULATE ( [Total Flights], fact_flight[is_operated] = 1 )
)

Cancellation Rate =
DIVIDE (
    CALCULATE ( [Total Flights], fact_flight[is_cancelled] = 1 ),
    [Total Flights]
)

Average Passenger Age = AVERAGE ( dim_passenger[age] )

Snapshot Flights = SUM ( fact_daily_country_snapshot[flight_count] )

Zero-Flight Country Days =
CALCULATE (
    COUNTROWS ( fact_daily_country_snapshot ),
    fact_daily_country_snapshot[flight_count] = 0
)
```

Measure lengkap (termasuk ranking, rolling 30 hari, target, passenger share)
ada di `powerbi/measures.dax`.

### 6.4 Halaman dashboard

**Page 1 — Ringkasan Eksekutif**

| Visual | Fields |
|---|---|
| Card Total Flights | `Total Flights` |
| Card On-Time Rate | `On-Time Rate` |
| Card Cancellation Rate | `Cancellation Rate` |
| Card Average Age | `Average Passenger Age` |
| Line chart tren bulanan | Axis `dim_date[month_year]`, Values `Total Flights`, `On-Time Rate` |
| Donut status | Legend `dim_flight_status[status_name]`, Values `Total Flights` |
| Bar Top 10 negara | Axis `dim_country[country_name]`, Values `Total Flights`, filter Top N = 10 |
| Filled map | Location `dim_country[country_name]`, Size `Total Flights` |
| Slicer | `dim_date[year]`, `dim_country[continent_name]`, `dim_flight_status[status_name]` |

**Page 2 — Performa Bandara & Negara**

| Visual | Fields |
|---|---|
| Bar Top 15 bandara | Axis `dim_airport[airport_name]`, Values `Total Flights` |
| Bar On-Time Rate per negara | Axis `dim_country[country_name]`, Values `On-Time Rate` |
| Matrix geografi | Rows `continent_name` → `country_name` → `airport_name`; Values `Total Flights`, `Cancellation Rate` |
| Table bandara | `airport_name`, `country_name`, `Total Flights`, `On-Time Rate`, `Cancellation Rate` |

**Page 3 — Profil Penumpang**

| Visual | Fields |
|---|---|
| Column age band | Axis `dim_passenger[age_band]`, Values `Total Passengers` |
| Donut gender | Legend `dim_passenger[gender]`, Values `Total Passengers` |
| Bar Top 10 nationality | Axis `dim_passenger[nationality]`, Values `Total Passengers` |
| Card Average Age | `Average Passenger Age` |

**Page 4 — Operasi Harian (Snapshot)**

| Visual | Fields |
|---|---|
| Line chart harian | Axis `dim_date[full_date]`, Values `Snapshot Flights`, `Snapshot Cancellation Rate` |
| Card Zero-Flight Days | `Zero-Flight Country Days` |
| Card Average Daily Flights | `Average Daily Flights per Country` |
| Matrix negara × bulan | Rows `dim_country[country_name]`, Columns `dim_date[month_name]`, Values `Snapshot Flights` |

> Jangan mencampur measure `fact_flight` dan `fact_daily_country_snapshot`
> dalam satu visual. Keduanya fact berbeda; gunakan halaman/visual terpisah.

Panduan visual yang lebih detail ada di `powerbi/dashboard-guide.md`.

![Rancangan tata letak dashboard](docs/dashboard-layout.png)

> Gambar di atas adalah **mockup rancangan tata letak**, bukan screenshot
> Power BI. Gunakan sebagai acuan susunan visual saat merakit dashboard.

### 6.5 Operasi OLAP

| Operasi | Cara |
|---|---|
| **Roll-up** | Matrix: `continent_name` → `country_name` → `airport_name`; tanggal: `year` → `quarter` → `month_name` |
| **Drill-down** | Klik ikon drill pada matrix/line chart |
| **Slice** | Slicer `dim_flight_status[status_name]` atau `dim_country[continent_name]` |
| **Dice** | Kombinasi slicer benua + bulan + gender + status |
| **Pivot** | Matrix: rows `country_name`, columns `month_name`, values `Total Flights` dan `Cancellation Rate` |

### 6.6 Refresh dan publish

- **Refresh**: Home → Refresh. Karena mode Import, data diambil ulang dari PostgreSQL.
- **Publish**: File → Publish → pilih workspace.
- Untuk refresh terjadwal, pasang gateway jika database tidak dapat diakses cloud.

---

## 7. Validasi Hasil

Jalankan:

```bash
psql -U postgres -d airline -f database/validation.sql
```

Ekspektasi:

| Cek | Hasil |
|---|---|
| `oltp.flights` | 98.619 |
| `dw.fact_flight` | 98.619 |
| `dw.fact_daily_country_snapshot` | 85.775 |
| Jumlah `flight_count` snapshot | 98.619 |
| Orphan fact → dimension | 0 |
| Bandara dengan 2 versi (SCD2) | 4 |
| Flight dengan versi salah | 0 |
| Total flights | 98.619 |
| Operated flights | 65.677 |
| On-time flights | 32.846 |
| Delayed flights | 32.831 |
| Cancelled flights | 32.942 |
| On-Time Rate | 50,01% |
| Delay Rate | 49,99% |
| Cancellation Rate | 33,40% |
| Average passenger age | 45,5 tahun |

KPI bulanan bisa dilihat lewat:

```sql
SELECT * FROM dw.v_monthly_kpi ORDER BY month_number;
```

---

## 8. Troubleshooting

### 8.1 Pentaho

| Gejala | Penyebab | Solusi |
|---|---|---|
| `Unrecognized VM option 'MaxPermSize=256m'` | PDI 7 dijalankan dengan Java 17 | Gunakan Java 8, atau hapus opsi `MaxPermSize` dari script PDI |
| `The authentication type 10 is not supported` | Driver PostgreSQL lama (9.3) tidak mendukung SCRAM | Ganti `lib/postgresql-*.jar` dengan `postgresql-42.7.x.jar` |
| `Field [airport_key] is required and couldn't be found` | Mapping key step Update terbalik | Di step **Update**, `<name>` = nama field di stream, `<field>` = nama kolom tabel. File yang disertakan sudah benar |
| `duplicate key value violates unique constraint "uq_dim_airport_version"` | Insert versi baru dijalankan sebelum versi lama ditutup | Jalankan `06_close_airport_versions` lalu `07_insert_airport_versions` (job sudah mengatur urutannya) |
| `Relation "dw.dim_airport" does not exist` | `warehouse.sql` belum dijalankan | Jalankan `psql -f database/warehouse.sql` |
| Job berhenti setelah Start | Hop pertama bersifat conditional | File job yang disertakan sudah memakai hop unconditional dari Start |
| `password authentication failed` | Password/pg_hba berbeda | Sesuaikan koneksi `OLTP` dan `DW` di setiap `.ktr` |
| ETL lambat di faktur | 98 ribu baris + banyak join | Normal; faktur di-truncate dan di-load ulang. Pastikan index `warehouse.sql` sudah dibuat |

### 8.2 Power BI

| Gejala | Solusi |
|---|---|
| PostgreSQL tidak muncul di Get Data | Install Npgsql/provider PostgreSQL, restart Power BI |
| Relasi tidak bisa dibuat | Pastikan tipe kolom sama. Semua `*_key` di fact dan dimension bertipe `int`; `flight_id` bertipe `bigint` dan tidak direlasikan ke dimension |
| Measure rate kosong | Periksa relasi dan filter context; `DIVIDE` mengembalikan blank jika denominator 0 |
| Angka status tidak konsisten | Gunakan denominator yang benar: on-time/delay = operated, cancellation = semua flight |
| Visual snapshot kosong | Pastikan memakai measure snapshot dan relasi `snapshot_date_key`/`country_key` |
| Tanggal tidak bisa drill-down | Tandai `dim_date` sebagai date table dan gunakan `full_date` |

---

## 9. Catatan Data dan Keterbatasan

### 9.1 Apa yang ada di dataset

Dataset berisi 98.619 baris dengan kolom:

- identitas penumpang: `Passenger ID`, nama, gender, age, nationality;
- bandara: `Airport Name`, `Airport Country Code`, `Country Name`, `Airport Continent`, `Continents`;
- tanggal: `Departure Date` (2022, dua format);
- `Arrival Airport`, `Pilot Name`, `Flight Status` (On Time / Delayed / Cancelled).

### 9.2 Temuan kualitas data

1. **`Arrival Airport` bukan bandara tujuan.** Pada 74.063 dari 74.720 baris
   yang bandaranya bisa dipetakan, kode di kolom ini sama dengan bandara
   keberangkatan. Jadi kolom ini dipakai sebagai **kode IATA bandara asal**,
   bukan untuk analisis rute.
2. **Tidak ada waktu.** Tidak ada scheduled/actual departure/arrival, sehingga
   on-time departure < 15 menit dan average delay minutes tidak bisa dihitung.
3. **Tidak ada aircraft, kapasitas, load factor, atau durasi/alasan delay.**
4. **Status terdistribusi hampir merata**: On Time 32.846 (33,31%),
   Delayed 32.831 (33,29%), Cancelled 32.942 (33,40%). Angka cancellation
   33,40% adalah karakteristik dataset, bukan benchmark industri.
5. **Nama pilot hampir unik** (98.605 nama untuk 98.619 baris), sehingga
   analisis produktivitas pilot tidak bermakna.
6. **Airport sangat long-tail**: 9.107 bandara, bandara tersibuk hanya 36 flight.
7. **84 bandara tidak memiliki kode IATA valid**; kolom `iata_code` disimpan
   `NULL` (bukan string `NaN`).

### 9.3 KPI yang dipakai (hasil adaptasi)

| KPI | Formula | Catatan |
|---|---|---|
| Total Flights | `COUNT(*) fact_flight` | 1 baris = 1 passenger flight record |
| On-Time Rate | On Time / operated | Status `On Time`; denominator tanpa cancelled |
| Delay Rate | Delayed / operated | Status `Delayed` |
| Cancellation Rate | Cancelled / semua flight | Denominator semua record |
| Average Passenger Age | `AVG(dim_passenger.age)` | Profil penumpang |
| Flights per Day | Total flights / jumlah hari | Tren volume |
| Snapshot Flights | `SUM(fact_daily_country_snapshot.flight_count)` | Periodic snapshot |
| Zero-Flight Country Days | Jumlah snapshot `flight_count = 0` | Hari tanpa flight per negara |

KPI yang **tidak** dihitung: on-time departure < 15 menit, average delay
minutes, load factor, aircraft utilization, delay reason. Alasannya ada di 9.2.

### 9.4 Mengapa model ini tetap valid sebagai proyek BI

- Grain dan relasi jelas: 1 baris = 1 passenger flight record.
- Ada dua tipe fact: transactional dan periodic snapshot.
- Ada SCD Type 0, 1, dan 2 yang benar-benar diuji.
- ETL Pentaho benar-benar dijalankan dan divalidasi.
- Dashboard memakai KPI yang benar-benar didukung data, bukan angka fiktif.
- Keterbatasan data didokumentasikan, bukan disembunyikan.

---

## 10. Status Pengujian

| Komponen | Status |
|---|---|
| PostgreSQL 15.20 — schema OLTP + load 98.619 baris | ✅ Diuji |
| PostgreSQL 15.20 — star schema + index | ✅ Diuji |
| Python loader (2 format tanggal, 9.107 bandara) | ✅ Diuji |
| Pentaho 7.0 + Java 8 — 9 transformation + 1 job | ✅ Diuji headless (`kitchen.sh`) |
| ETL load awal (2022-01-01) | ✅ 98.619 fact, 85.775 snapshot |
| SCD Type 1 (Turkey → Türkiye) | ✅ 704 flight menampilkan nilai baru |
| SCD Type 2 (4 bandara) | ✅ 8 baris versi, 0 flight dengan versi salah |
| Rekonsiliasi fact vs snapshot | ✅ 98.619 = 98.619 |
| `database/validation.sql` | ✅ Semua cek lolos |
| Power BI Desktop | ⚠️ Manual — tidak tersedia di Linux |
| File `.pbix` | ❌ Tidak disertakan; rakit mengikuti bagian 6 |
| Diagram ERD, star schema, ETL flow, layout | ✅ Ada di `docs/` |

---

## Ringkasan Angka untuk Presentasi

- **98.619** passenger flight record, **9.107** bandara, **235** negara,
  **98.605** pilot, **98.619** penumpang.
- **50,01%** on-time rate dari **65.677** operated flights.
- **49,99%** delay rate; **33,40%** cancellation rate.
- **45,5 tahun** rata-rata umur penumpang; gender hampir seimbang
  (Male 50,29% / Female 49,71%).
- **United States 22,41%** dari volume; bandara tersibuk hanya **36 flight**
  (distribusi long-tail).
- **85.775** baris snapshot (235 negara × 365 hari); **55.358** country-days
  tanpa flight (64,54%).
- **4 bandara** memiliki 2 versi SCD Type 2; **0** flight memakai versi salah.
