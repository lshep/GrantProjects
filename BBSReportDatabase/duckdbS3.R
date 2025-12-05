library(duckdb)		
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL httpfs;")
dbExecute(con, "LOAD httpfs;")

dbExecute(con, "CREATE OR REPLACE SECRET s3_secret (TYPE S3, PROVIDER credential_chain);")

s3_url <- "s3://bioc-builddb-mirror/buildResults/0015761b48700798e7a4cc3e0d5a3e00-build_summary.csv.gz"

result <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_url, "')", sep = ""))

dbDisconnect(con)
