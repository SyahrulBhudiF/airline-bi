#!/usr/bin/env python3
"""
Load the provided airline dataset into the OLTP schema.

Source : data/raw/Airline-Dataset-Updated-v2.csv.zip
Target : PostgreSQL schema oltp (database/oltp.sql must be executed first)

The CSV has one row per passenger flight record. It contains no scheduled/
actual times, aircraft, seat capacity, or delay duration, so the OLTP model
only stores fields that actually exist in the data.

Usage:
    python data/load_data.py
    python data/load_data.py --dsn postgresql://postgres:postgres@localhost:5432/airline
"""

from __future__ import annotations

import argparse
import math
import os
import re
from datetime import datetime
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_CSV = BASE_DIR / "raw" / "Airline-Dataset-Updated-v2.csv.zip"
DEFAULT_DSN = os.environ.get(
    "AIRLINE_DSN", "postgresql://postgres:postgres@localhost:5432/airline"
)
DEFAULT_REPORT = BASE_DIR / "data-quality-report.txt"

CONTINENT_NAMES = {
    "AF": "Africa",
    "AS": "Asia",
    "EU": "Europe",
    "NAM": "North America",
    "OC": "Oceania",
    "SAM": "South America",
}

STATUS_MAP = {
    "On Time": ("ONT", "On Time", 1, 0),
    "Delayed": ("DLY", "Delayed", 1, 0),
    "Cancelled": ("CNL", "Cancelled", 0, 1),
}


def parse_date(value: str):
    """Dataset mixes m/d/Y and d-m-Y formats."""
    value = str(value).strip()
    for fmt in ("%m/%d/%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None


def optional(value):
    """Convert pandas NaN/None into a real SQL NULL."""
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    return value


def clean_frame(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df.columns = [
        "passenger_id", "first_name", "last_name", "gender", "age",
        "nationality", "airport_name", "country_code", "country_name",
        "continent_code", "continent_name", "departure_date",
        "arrival_airport", "pilot_name", "flight_status",
    ]

    for col in ("passenger_id", "first_name", "last_name", "gender",
                "nationality", "airport_name", "country_code", "country_name",
                "continent_code", "continent_name", "arrival_airport",
                "pilot_name", "flight_status"):
        df[col] = df[col].str.strip()

    df["country_code"] = df["country_code"].str.upper()
    df["continent_code"] = df["continent_code"].str.upper()
    df["arrival_airport"] = df["arrival_airport"].str.upper()
    df["age"] = pd.to_numeric(df["age"], errors="coerce").astype("Int64")
    df["flight_date"] = df["departure_date"].map(parse_date)

    bad_dates = df["flight_date"].isna().sum()
    if bad_dates:
        raise ValueError(f"{bad_dates} rows have an unparseable Departure Date")

    # The column "Arrival Airport" actually contains the IATA code of the
    # departure airport for the vast majority of rows. Use it as the airport
    # code, taking the most frequent valid code per airport.
    valid_code = df["arrival_airport"].str.fullmatch(r"[A-Z]{3}")
    code_by_airport = (
        df.loc[valid_code]
        .groupby(["airport_name", "country_code"])["arrival_airport"]
        .agg(lambda s: s.value_counts().idxmax())
        .to_dict()
    )
    df["iata_code"] = [
        code_by_airport.get((name, country))
        for name, country in zip(df["airport_name"], df["country_code"])
    ]
    df["recorded_arrival_code"] = df["arrival_airport"].where(valid_code, None)

    # Keep one row per passenger id; the dataset has no duplicate ids, but
    # this makes the loader safe to re-run on a dirty extract.
    df = df.drop_duplicates(subset=["passenger_id"], keep="first").reset_index(drop=True)
    return df


def load(df: pd.DataFrame, dsn: str) -> dict:
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    stats = {}
    try:
        with conn.cursor() as cur:
            cur.execute("""
                TRUNCATE oltp.flights, oltp.passengers, oltp.pilots,
                         oltp.airports, oltp.countries
                RESTART IDENTITY CASCADE
            """)

            countries = (
                df[["country_code", "country_name", "continent_code"]]
                .drop_duplicates(subset=["country_code"])
                .sort_values("country_code")
            )
            country_rows = [
                (r.country_code, r.country_name, r.continent_code,
                 CONTINENT_NAMES.get(r.continent_code, r.continent_code))
                for r in countries.itertuples()
            ]
            execute_values(
                cur,
                "INSERT INTO oltp.countries "
                "(country_code, country_name, continent_code, continent_name) VALUES %s",
                country_rows,
            )

            airports = (
                df[["airport_name", "country_code", "iata_code"]]
                .drop_duplicates(subset=["airport_name", "country_code"])
                .sort_values(["country_code", "airport_name"])
                .reset_index(drop=True)
            )
            airports["airport_id"] = airports.index + 1
            airport_key = {
                (r.airport_name, r.country_code): int(r.airport_id)
                for r in airports.itertuples()
            }
            execute_values(
                cur,
                "INSERT INTO oltp.airports "
                "(airport_id, iata_code, airport_name, country_code) VALUES %s",
                [
                    (int(r.airport_id), optional(r.iata_code), r.airport_name, r.country_code)
                    for r in airports.itertuples()
                ],
            )
            stats["airports"] = len(airports)
            stats["airports_without_iata"] = int(airports["iata_code"].isna().sum())

            pilots = (
                df[["pilot_name"]].drop_duplicates().sort_values("pilot_name")
                .reset_index(drop=True)
            )
            pilots["pilot_id"] = pilots.index + 1
            pilot_key = dict(zip(pilots["pilot_name"], pilots["pilot_id"]))
            execute_values(
                cur,
                "INSERT INTO oltp.pilots (pilot_id, pilot_name) VALUES %s",
                [(int(r.pilot_id), r.pilot_name) for r in pilots.itertuples()],
            )
            stats["pilots"] = len(pilots)

            passenger_rows = [
                (r.passenger_id, r.first_name, r.last_name, r.gender,
                 int(r.age), r.nationality)
                for r in df.itertuples()
            ]
            execute_values(
                cur,
                "INSERT INTO oltp.passengers "
                "(passenger_id, first_name, last_name, gender, age, nationality) VALUES %s",
                passenger_rows,
                page_size=2000,
            )
            stats["passengers"] = len(passenger_rows)

            status_id = {"ONT": 1, "DLY": 2, "CNL": 3}
            flight_rows = [
                (i + 1, r.flight_date, airport_key[(r.airport_name, r.country_code)],
                 int(pilot_key[r.pilot_name]), r.passenger_id,
                 status_id[STATUS_MAP[r.flight_status][0]],
                 optional(r.recorded_arrival_code))
                for i, r in enumerate(df.itertuples())
            ]
            execute_values(
                cur,
                "INSERT INTO oltp.flights "
                "(flight_id, flight_date, origin_airport_id, pilot_id, "
                " passenger_id, status_id, recorded_arrival_code) VALUES %s",
                flight_rows,
                page_size=2000,
            )
            stats["flights"] = len(flight_rows)

            for table, column in (
                ("airports", "airport_id"),
                ("pilots", "pilot_id"),
                ("flights", "flight_id"),
            ):
                cur.execute(
                    f"SELECT setval(pg_get_serial_sequence('oltp.{table}', '{column}'), "
                    f"(SELECT MAX({column}) FROM oltp.{table}))"
                )
            cur.execute("ANALYZE oltp.flights")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return stats


def write_report(df: pd.DataFrame, stats: dict, path: Path, source: Path) -> None:
    status = df["flight_status"].value_counts()
    mismatch = (df["iata_code"].notna() &
                (df["recorded_arrival_code"].notna()) &
                (df["iata_code"] != df["recorded_arrival_code"])).sum()
    lines = [
        "AIRLINE DATASET - DATA QUALITY REPORT",
        "=" * 45,
        f"Source file        : {source.name}",
        f"Rows in CSV        : {len(df):,}",
        f"Rows loaded        : {stats['flights']:,}",
        f"Unique passengers  : {df['passenger_id'].nunique():,}",
        f"Unique pilots      : {stats['pilots']:,}",
        f"Airports           : {stats['airports']:,}",
        f"Airports tanpa IATA: {stats['airports_without_iata']:,}",
        f"Countries          : {df['country_code'].nunique():,}",
        f"Date range         : {df['flight_date'].min()} s/d {df['flight_date'].max()}",
        "",
        "Status distribution:",
        *[f"  {k:<10} {v:>8,} ({v/len(df):6.2%})" for k, v in status.items()],
        "",
        "Data quality notes:",
        "  1. Kolom 'Arrival Airport' berisi kode IATA bandara KEBERANGKATAN",
        "     pada hampir seluruh baris (bukan bandara tujuan).",
        f"     Baris dengan kode berbeda dari bandara asal: {mismatch:,}.",
        "  2. Tidak ada scheduled/actual departure time, aircraft, kapasitas",
        "     kursi, durasi delay, atau alasan delay di dataset.",
        "  3. Setiap passenger_id unik; satu baris = satu passenger flight record.",
        "  4. Nama pilot tidak unik sepenuhnya; duplikasi nama digabung.",
        "  5. Tanggal memakai dua format (m/d/Y dan d-m-Y) dan sudah dinormalisasi.",
        "",
        "Model consequence:",
        "  KPI berbasis waktu keberangkatan, load factor, aircraft utilization,",
        "  dan rata-rata menit delay TIDAK dapat dihitung dari dataset ini.",
        "  KPI yang dipakai: volume flight, on-time rate, delay rate,",
        "  cancellation rate, traffic per airport/country, dan profil penumpang.",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--dsn", default=DEFAULT_DSN)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    if not args.csv.exists():
        raise SystemExit(f"CSV not found: {args.csv}")

    print(f"Reading {args.csv} ...")
    df = clean_frame(args.csv)
    print(f"Cleaned rows: {len(df):,}")

    print("Loading into PostgreSQL ...")
    stats = load(df, args.dsn)
    print(f"Loaded {stats['flights']:,} flights, {stats['passengers']:,} passengers, "
          f"{stats['airports']:,} airports, {stats['pilots']:,} pilots.")

    write_report(df, stats, args.report, args.csv)
    print(f"Data quality report: {args.report}")


if __name__ == "__main__":
    main()
