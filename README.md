# Airline BI Project

Implementasi Business Intelligence untuk analisis kinerja operasional
penerbangan: PostgreSQL (OLTP + data warehouse), Pentaho Data Integration
(ETL), dan Power BI (dashboard).

**Tutorial lengkap — setup database, menjalankan ETL Pentaho, demo SCD, dan
merakit dashboard Power BI — ada di:**

## [airline-bi/README.md](airline-bi/README.md)

File penting:

- [`airline-bi/database/oltp.sql`](airline-bi/database/oltp.sql) — schema OLTP
- [`airline-bi/database/warehouse.sql`](airline-bi/database/warehouse.sql) — star schema
- [`airline-bi/pentaho/jobs/load_warehouse.kjb`](airline-bi/pentaho/jobs/load_warehouse.kjb) — job ETL
- [`airline-bi/powerbi/measures.dax`](airline-bi/powerbi/measures.dax) — DAX measures
- [`airline-bi/docs/star-schema.png`](airline-bi/docs/star-schema.png) — diagram star schema
