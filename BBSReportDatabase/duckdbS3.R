library(duckdb)
library(duckplyr)
library(stringr)

s3_summary_url <- "s3://bioc-builddb-mirror/buildResults/*-build_summary.csv.gz"
s3_info_url <- "s3://bioc-builddb-mirror/buildResults/*-info.csv.gz"
s3_propagation_url <- "s3://bioc-builddb-mirror/buildResults/*-propagation_status.csv.gz"
  
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL httpfs;")
dbExecute(con, "LOAD httpfs;")

dbExecute(con, "CREATE OR REPLACE SECRET s3_secret (TYPE S3, PROVIDER credential_chain);")

## s3_url <- "s3://bioc-builddb-mirror/buildResults/0015761b48700798e7a4cc3e0d5a3e00-build_summary.csv.gz"
## result <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_url, "')", sep = ""))

## start with summary files
result <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_summary_url, "')", sep = ""))



result |>
    filter(package == "BiocFileCache", str_starts(node, "nebbiolo"), status == "ERROR") |>
    arrange(node, startedat) |>
    mutate(version_group = if_else(
               package_version(version) < package_version("3.0.0"),
               "<3",
               ">=3"
           )
           ) |>
    count(node, version_group, stage)




dbDisconnect(con)
