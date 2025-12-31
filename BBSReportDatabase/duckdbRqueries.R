library(duckdb)
library(DBI)
library(duckplyr)

con <- dbConnect(duckdb(), dbdir = "bioc_builddb.duckdb")

dbGetQuery(con, "
SELECT package, version
FROM latest_build_per_package
WHERE NOT all_stages_ok
")


dbDisconnect(con, shutdown = TRUE)
