## AI assisted 


library(DBI)
library(duckdb)

## ------------------------------------------------------------------
## Configuration
## ------------------------------------------------------------------

db_file <- "bioc_builddb.duckdb"

summary_url <- "s3://bioc-builddb-mirror/parquet/build_summary.parquet"
info_url    <- "s3://bioc-builddb-mirror/parquet/info.parquet"
prop_url    <- "s3://bioc-builddb-mirror/parquet/propagation_status.parquet"

## ------------------------------------------------------------------
## Connect (persistent)
## ------------------------------------------------------------------

con <- dbConnect(duckdb(), dbdir = db_file)

dbExecute(con, "INSTALL httpfs")
dbExecute(con, "LOAD httpfs")

## ------------------------------------------------------------------
## Step 1: Ingest + normalize (materialized tables)
## ------------------------------------------------------------------

dbExecute(con, sprintf("
CREATE OR REPLACE TABLE summary_t AS
SELECT
  lower(package) AS package,
  version,
  node,
  stage,
  status,
  startedat,
  endedat,
  command,
  report_md5
FROM read_parquet('%s')
", summary_url))

dbExecute(con, sprintf("
CREATE OR REPLACE TABLE info_t AS
SELECT
  lower(Package) AS package,
  Version        AS version,
  Maintainer,
  MaintainerEmail,
  git_url,
  git_branch,
  git_last_commit,
  git_last_commit_date,
  report_md5
FROM read_parquet('%s')
", info_url))

dbExecute(con, sprintf("
CREATE OR REPLACE TABLE propagation_t AS
SELECT
  lower(package) AS package,
  process,
  propagate,
  report_md5
FROM read_parquet('%s')
", prop_url))

## ------------------------------------------------------------------
## Step 2: Base reusable views (cheap, flexible)
## ------------------------------------------------------------------

dbExecute(con, "
CREATE OR REPLACE VIEW summary_v AS
SELECT * FROM summary_t
")

dbExecute(con, "
CREATE OR REPLACE VIEW info_v AS
SELECT * FROM info_t
")

dbExecute(con, "
CREATE OR REPLACE VIEW propagation_v AS
SELECT * FROM propagation_t
")

## ------------------------------------------------------------------
## Step 3: Derived analytics views
## ------------------------------------------------------------------

## Build × stage × process (max detail)
dbExecute(con, "
CREATE OR REPLACE VIEW build_stage_detail AS
SELECT
  s.package,
  s.version,
  s.node,
  s.stage,
  s.status,
  s.startedat,
  s.endedat,
  i.git_branch,
  i.git_last_commit,
  p.process,
  p.propagate,
  s.report_md5
FROM summary_v s
LEFT JOIN info_v i
  USING (package, version, report_md5)
LEFT JOIN propagation_v p
  USING (package, report_md5)
")

## One row per build
dbExecute(con, "
CREATE OR REPLACE VIEW build_overview AS
SELECT
  s.package,
  s.version,
  s.report_md5,
  max(i.git_branch)        AS git_branch,
  max(i.git_last_commit)  AS git_last_commit,
  bool_and(s.status = 'OK') AS all_stages_ok,
  count(DISTINCT s.stage) AS n_stages,
  min(s.startedat)        AS build_started,
  max(s.endedat)          AS build_finished,
  string_agg(DISTINCT p.process, ', ') AS processes
FROM summary_v s
LEFT JOIN info_v i
  USING (package, version, report_md5)
LEFT JOIN propagation_v p
  USING (package, report_md5)
GROUP BY
  s.package, s.version, s.report_md5
")

## Latest build per package
dbExecute(con, "
CREATE OR REPLACE VIEW latest_build_per_package AS
SELECT *
FROM build_overview
QUALIFY
  row_number() OVER (
    PARTITION BY package
    ORDER BY build_started DESC
  ) = 1
")

## ------------------------------------------------------------------
## Optional: indexes (persist across sessions)
## ------------------------------------------------------------------

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_summary_pkg
ON summary_t(package)
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_summary_md5
ON summary_t(report_md5)
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_build_overview_pkg
ON summary_t(package)
")

## ------------------------------------------------------------------
## Done
## ------------------------------------------------------------------

message("Local DuckDB database ready: ", db_file)
message("Remote parquet files no longer needed for analysis.")

dbDisconnect(con, shutdown = TRUE)
