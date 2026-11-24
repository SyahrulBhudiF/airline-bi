# Panduan Dashboard Power BI

Panduan ini menjelaskan cara merakit dashboard dari data warehouse `airline`
menggunakan Power BI Desktop. File `.pbix` tidak disertakan karena Power BI
Desktop tidak tersedia di lingkungan Linux tempat proyek ini dibangun; seluruh
langkah di bawah sudah disesuaikan dengan struktur tabel dan measure yang ada.

---

## 1. Prasyarat

- Power BI Desktop (Windows).
- PostgreSQL berjalan di `localhost:5432`, database `airline`.
- Kredensial default proyek: user `postgres`, password `postgres`
  (ubah sesuai instalasi Anda).
- Driver Npgsql PostgreSQL terpasang (Power BI Desktop biasanya sudah
  menyertakan provider PostgreSQL; jika belum, instal Npgsql 4.1+).

---

## 2. Menghubungkan Power BI ke Data Warehouse

1. Buka **Power BI Desktop → Get Data → More → Database → PostgreSQL database**.
2. Isi:
   - **Server**: `localhost:5432`
   - **Database**: `airline`
   - **Data Connectivity mode**: `Import`
3. Klik **OK**, masukkan kredensial database.
4. Pilih tabel berikut (schema `dw`):

| Tabel | Peran |
|---|---|
| `fact_flight` | Fact transaksional, grain = 1 passenger flight record |
| `fact_daily_country_snapshot` | Fact periodic snapshot, grain = 1 negara × 1 hari |
| `dim_date` | Dimensi tanggal |
| `dim_airport` | Dimensi bandara (SCD Type 2) |
| `dim_country` | Dimensi negara (SCD Type 1) |
| `dim_passenger` | Dimensi penumpang |
| `dim_pilot` | Dimensi pilot |
| `dim_flight_status` | Dimensi status penerbangan |

5. Klik **Load**.

---

## 3. Relasi Model

Buka **Model view**, buat relasi berikut (semua **one-to-many**, arah filter
single dari dimensi ke fact):

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
  menyimpan `country_code`, bukan `country_key`. Filter negara tetap bekerja
  melalui fact.
- Tandai `dim_date` sebagai **Mark as date table** menggunakan `full_date`.
- Urutkan `dim_date[month_name]` berdasarkan `month_number`, dan
  `dim_date[day_name]` berdasarkan `day_of_week`.
- Sembunyikan kolom teknis (`*_key`, `valid_from`, `valid_to`, `version`)
  dari **Report view**.

---

## 4. Membuat Measure

1. Buat tabel measure kosong: **Home → Enter Data**, beri nama `_Measures`,
   satu kolom `Placeholder`, klik **Load**. Sembunyikan kolom `Placeholder`.
2. Buka `powerbi/measures.dax`, lalu buat setiap measure dengan
   **Modeling → New Measure** di tabel `_Measures`.
3. Format angka:
   - `Total Flights`, `Total Passengers`, `Operated Flights`,
     `On-Time Flights`, `Delayed Flights`, `Cancelled Flights`:
     **Whole Number**, ribuan dipisah koma.
   - `On-Time Rate`, `Delay Rate`, `Cancellation Rate`,
     `On-Time Rate (All Scheduled)`, `Passenger Share`,
     `Snapshot On-Time Rate`, `Snapshot Cancellation Rate`,
     `On-Time Gap`, `Cancellation Gap`: **Percentage**, 1 desimal.
   - `Average Passenger Age`: **Decimal**, 1 desimal.
   - `Flights per Day`, `Average Daily Flights per Country`,
     `Rolling 30-Day Flights`: **Decimal**, 1 desimal.

Measure utama yang dipakai di dashboard:

| Measure | Definisi |
|---|---|
| `Total Flights` | Jumlah passenger flight record |
| `On-Time Rate` | On Time / operated flights |
| `Delay Rate` | Delayed / operated flights |
| `Cancellation Rate` | Cancelled / seluruh flight record |
| `Average Passenger Age` | Rata-rata umur penumpang |
| `Flights per Day` | Total flights / jumlah hari terpilih |
| `Snapshot Flights` | Jumlah flight dari fact snapshot |
| `Zero-Flight Country Days` | Negara-hari tanpa flight |

---

## 5. Rancangan Halaman Dashboard

### Halaman 1 — Ringkasan Eksekutif

Tujuan: gambaran cepat volume, ketepatan waktu, pembatalan, dan sebaran wilayah.

| Visual | Tipe | Fields |
|---|---|---|
| KPI Total Flights | Card | `Total Flights` |
| KPI On-Time Rate | Card | `On-Time Rate` |
| KPI Cancellation Rate | Card | `Cancellation Rate` |
| KPI Average Age | Card | `Average Passenger Age` |
| Tren bulanan | Line chart | Axis `dim_date[month_year]`, Values `Total Flights`, `On-Time Rate` |
| Komposisi status | Donut chart | Legend `dim_flight_status[status_name]`, Values `Total Flights` |
| Top 10 negara | Bar chart | Axis `dim_country[country_name]`, Values `Total Flights`; filter Top N = 10 |
| Peta sebaran | Filled map | Location `dim_country[country_name]`, Size `Total Flights` |
| Filter | Slicer | `dim_date[year]`, `dim_country[continent_name]`, `dim_flight_status[status_name]` |

### Halaman 2 — Performa Bandara & Negara

Tujuan: roll-up dan drill-down geografis.

| Visual | Tipe | Fields |
|---|---|---|
| Top 15 bandara | Bar chart | Axis `dim_airport[airport_name]`, Values `Total Flights`; filter Top N = 15 |
| On-time rate per negara | Bar chart | Axis `dim_country[country_name]`, Values `On-Time Rate`; filter Top N = 15 by `Total Flights` |
| Matriks geografi | Matrix | Rows `dim_country[continent_name]`, `dim_country[country_name]`, `dim_airport[airport_name]`; Values `Total Flights`, `Cancellation Rate` |
| Tabel bandara | Table | `dim_airport[airport_name]`, `dim_country[country_name]`, `Total Flights`, `On-Time Rate`, `Cancellation Rate` |
| Filter | Slicer | `dim_country[continent_name]`, `dim_flight_status[status_name]`, `dim_date[year]` |

### Halaman 3 — Profil Penumpang

Tujuan: komposisi demografis penumpang.

| Visual | Tipe | Fields |
|---|---|---|
| Distribusi umur | Column chart | Axis `dim_passenger[age_band]`, Values `Total Passengers` |
| Gender | Donut chart | Legend `dim_passenger[gender]`, Values `Total Passengers` |
| Top 10 nationalities | Bar chart | Axis `dim_passenger[nationality]`, Values `Total Passengers`; filter Top N = 10 |
| Rata-rata umur | Card | `Average Passenger Age` |
| Filter | Slicer | `dim_passenger[gender]`, `dim_passenger[age_band]`, `dim_country[continent_name]` |

### Halaman 4 — Operasi Harian (Periodic Snapshot)

Tujuan: memanfaatkan `fact_daily_country_snapshot` dan menunjukkan hari tanpa
flight (zero-flight days).

| Visual | Tipe | Fields |
|---|---|---|
| Tren harian | Line chart | Axis `dim_date[full_date]`, Values `Snapshot Flights`, `Snapshot Cancellation Rate` |
| Zero-flight days | Card | `Zero-Flight Country Days` |
| Rata-rata flight per negara/hari | Card | `Average Daily Flights per Country` |
| Matriks negara × bulan | Matrix | Rows `dim_country[country_name]`, Columns `dim_date[month_name]`, Values `Snapshot Flights` |
| Filter | Slicer | `dim_date[full_date]`, `dim_country[continent_name]` |

> Penting: jangan mencampur measure dari `fact_flight` dan
> `fact_daily_country_snapshot` dalam satu visual. Keduanya fact berbeda;
> gunakan halaman terpisah atau visual terpisah.

---

## 6. Operasi OLAP di Dashboard

| Operasi | Implementasi |
|---|---|
| **Roll-up** | Matriks geografi: `continent_name` → `country_name` → `airport_name`; tanggal: `year` → `quarter` → `month_name`. |
| **Drill-down** | Klik ikon drill pada matriks/line chart; gunakan hierarchy tanggal dan geografi. |
| **Slice** | Slicer status (`On Time` / `Delayed` / `Cancelled`) atau slicer benua. |
| **Dice** | Kombinasi slicer benua + bulan + gender + status pada satu halaman. |
| **Pivot** | Matriks dengan `country_name` di Rows dan `month_name` di Columns, values `Total Flights` dan `Cancellation Rate`. |

---

## 7. Formatting

- Gunakan tema biru tua–teal yang konsisten dengan judul laporan.
- KPI card: angka besar, label kecil, warna merah untuk cancellation rate
  di atas 5% (conditional formatting).
- Line chart: sembunyikan gridline yang tidak perlu, tampilkan data label
  pada titik terakhir.
- Bar chart: urutkan descending, tampilkan Top N, beri data label.
- Map: gunakan filled map; pastikan kolom negara berisi nama negara.
- Tambahkan tooltip berisi `Total Flights`, `On-Time Rate`, dan
  `Cancellation Rate`.
- Sembunyikan halaman bantuan dan field teknis dari tampilan.

---

## 8. Publish (opsional)

1. **File → Publish → Publish to Power BI**.
2. Pilih workspace.
3. Atur scheduled refresh jika database dapat diakses oleh gateway.
4. Bagikan link dashboard.

---

## 9. Batasan yang Perlu Diketahui

Dataset sumber tidak memiliki:

- scheduled/actual departure dan arrival time,
- aircraft dan seat capacity,
- durasi delay dalam menit,
- alasan delay,
- bandara tujuan yang valid (kolom `Arrival Airport` berisi kode bandara
  keberangkatan pada hampir seluruh baris).

Karena itu dashboard **tidak** menampilkan on-time departure rate berbasis
15 menit, average delay minutes, load factor, aircraft utilization, atau
analisis rute. KPI yang ditampilkan berbasis status (`On Time`, `Delayed`,
`Cancelled`), volume, bandara/negara, profil penumpang, dan snapshot harian.
Penjelasan lengkap ada di `docs/final-report.pdf` bagian Keterbatasan.

---

## 10. Status Verifikasi

| Komponen | Status |
|---|---|
| Skema OLTP + load 98.619 record | Diuji di PostgreSQL 15 |
| Skema warehouse + star schema | Diuji di PostgreSQL 15 |
| ETL Pentaho (9 transformation + 1 job) | Diuji headless dengan Pentaho 7.0 + Java 8 |
| SCD Type 1 / Type 2 | Diuji dengan dua kali load dan `scd_demo.sql` |
| Validasi KPI dan rekonsiliasi fact | Diuji, lihat `database/validation.sql` |
| Power BI Desktop | Manual — tidak tersedia di lingkungan build |
| File `.pbix` | Tidak disertakan; rakit mengikuti panduan ini |
