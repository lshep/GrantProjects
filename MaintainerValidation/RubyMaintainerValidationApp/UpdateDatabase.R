library(dplyr)
library(stringr)
library(RSQLite)
library(DBI)
library(jsonlite)
library(httr2)

## change for live location
url_base = "http://127.0.0.1:4567"

debug=FALSE

files <- c(
    "https://www.bioconductor.org/packages/release/bioc/VIEWS",
    "https://www.bioconductor.org/packages/devel/bioc/VIEWS",
    "https://www.bioconductor.org/packages/release/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/devel/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/release/workflows/VIEWS",
    "https://www.bioconductor.org/packages/devel/workflows/VIEWS",
    "https://www.bioconductor.org/packages/release/data/annotation/VIEWS",
    "https://www.bioconductor.org/packages/devel/data/annotation/VIEWS")



emails_list <- list()

## Helper function: extract (name, email) pairs
##  used chatgpt to debug 
clean_name <- function(name) {
  ## Trim and collapse whitespace
  ## Remove ORCID-like IDs (e.g., 0000-0002-7688-6974)
  name <- str_squish(name)
  name <- gsub("\\b\\d{4}-\\d{4}-\\d{4}-\\d{4}\\b", "", name)
  name <- str_squish(name)
  return(name)
}

extract_name_email <- function(maintainer_string) {
  pattern <- "([^,<]+?)\\s*<([^>]+)>"
  matches <- str_match_all(maintainer_string, pattern)[[1]]
  if (nrow(matches) == 0) {
    return(data.frame(Name=character(0), Email=character(0), stringsAsFactors=FALSE))
  }  
  df <- data.frame(
    Name = sapply(str_trim(matches[, 2]), clean_name),
    Email = str_trim(matches[, 3]),
    stringsAsFactors = FALSE
  ) 
  return(df)
}

for (i in seq_along(files)) {
  temp <- read.dcf(url(files[i]))

  for (j in seq_len(nrow(temp))) {
    pkg_name <- temp[j, "Package"]
    maint_raw <- temp[j, "Maintainer"]

    name_email_df <- extract_name_email(maint_raw)

    if (nrow(name_email_df) > 0) {
      name_email_df$Package <- pkg_name
      emails_list[[length(emails_list) + 1]] <- name_email_df[, c("Package", "Name", "Email")]
    }
  }
}


email_df <- do.call(rbind, emails_list)
email_df$Package <- str_trim(email_df$Package)
email_df$Name    <- str_trim(email_df$Name)
email_df$Email   <- str_trim(email_df$Email)
email_df <- unique(email_df)


## > dim(email_df)
## [1] 3926    3

## make a test sub of email_df so can run again and test new insert
## email_df = email_df[-c(10:12, 200:210, 2200:2220, 3889:3890),]

## > dim(email_df)
## [1] 3889    3
##  so on rerun 37 added


## XINA  used and 
## anota2seq  used , 
## BEARscc  had /n
## XVector has special character name
## xcore has special character name
## are there other edge cases? else seems correct

## write.csv(email_df, file = "MaintainerEmailList.csv", row.names=FALSE)


## Now filter only unique emails (to potentially pass to validator)

## email_only <- unique(email_df[,"Email"])
## temp <- lapply(email_only, write, "EmailList.txt", append=TRUE)

## save.image("GetEmailList.RData")




## ------------------------------------------------------------------------------##
##
## Connect to Database
##
## ------------------------------------------------------------------------------## 

con <- dbConnect(RSQLite::SQLite(), "db.sqlite3")


dbExecute(con, "
CREATE TABLE IF NOT EXISTS maintainers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    package TEXT NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    consent_date DATE,
    pw_hash TEXT,
    email_status TEXT,
    is_email_valid BOOLEAN,
    UNIQUE(package, email));
")

existing_pairs <- dbGetQuery(con, "SELECT package, email FROM maintainers")

## ------------------------------------------------------------------------------##
##
##  Adding New Entries
##
## ------------------------------------------------------------------------------## 

is_new_pair <- function(pkg, email) {
  !any(existing_pairs$package == pkg & existing_pairs$email == email)
}

new_rows <- email_df[mapply(is_new_pair, email_df$Package, email_df$Email), ]

## test json to debug api addition rather than addition here


if(nrow(new_rows) > 0){

    to_insert <- data.frame(
        package = new_rows$Package,
        name = new_rows$Name,
        email = new_rows$Email,
        consent_date = as.character(Sys.Date()),
        pw_hash = NA,
        email_status = "valid",
        is_email_valid = TRUE
    )
    
    dbWriteTable(con, "maintainers", to_insert, append = TRUE, row.names = FALSE)
    message("Inserted ", nrow(to_insert), " new rows.")
} else {
    message("No new rows to insert.")
}


## ------------------------------------------------------------------------------##
##
##  Deleting Removed Entries
##
## ------------------------------------------------------------------------------## 


## create a removed entries
## email_df = email_df[-(1,2),]

current_pairs <- email_df %>%
  transmute(package = Package, email = Email) %>%
  distinct()

deleted_pairs <- anti_join(existing_pairs, current_pairs, by = c("package", "email"))

if (nrow(deleted_pairs) > 0) {

    if(debug) print(deleted_pairs)
    
    for (i in seq_len(nrow(deleted_pairs))) {
        dbExecute(con, "DELETE FROM maintainers WHERE package = ? AND email = ?",
                  params = list(deleted_pairs$package[i], deleted_pairs$email[i]))
    }
    
    message("Deleted ", nrow(deleted_pairs), " obsolete rows.")
} else {
    message("No rows to delete.")
}

## ------------------------------------------------------------------------------##
##
##  Trigger Email Verification
##
## ------------------------------------------------------------------------------## 

## query <- "UPDATE maintainers set consent_date='2024-02-14' where id IN (3901,3903,3898)"
## query <- "UPDATE maintainers set consent_date='2024-02-14' where package='BiocFileCache';
## dbExecute(con, query)

query <- "
SELECT id, name, email
FROM maintainers
WHERE consent_date IS NULL
  OR DATE(consent_date) <= DATE('now', '-1 year')
"

stale_consent <- dbGetQuery(con, query)

stale_unique <- stale_consent %>%
  distinct(name, email, .keep_all = TRUE)

if(debug) print(stale_unique)

# Save to JSON
if (nrow(stale_unique) > 0) {
  json_payload <- toJSON(stale_unique, pretty = TRUE, auto_unbox = TRUE, na = "null")
  email_url <- paste0(url_base, "/send-verification")
  response <- request(email_url) %>%
      req_headers("Content-Type" = "application/json") %>%
      req_body_raw(json_payload) %>%
      req_perform()
  if (resp_status(response) == 200){
      message("Verification request sent successfully")
  }else{
      warning("Failed to send verification request. Status: ", resp_status(response))
  }
} else {
  message("No stale consent entries found.")
}



## write sample json for ruby debugging
## write(json_payload, file = "mock_verification.json")

## Disconnect from database
dbDisconnect(con)


## write same json file for ruby debugging
## Adding packages through ruby endpoing
# Load jsonlite package for JSON handling

## maintainers <- list(
##   list(package = "pkgA", name = "Alice Example", email = "alice@example.com"),
##   list(package = "pkgB", name = "Bob Example", email = "bob@example.com"),
##   list(package = "pkgC", name = "Carol Example", email = "carol@example.com")
## )
## json_data <- toJSON(maintainers, pretty = TRUE, auto_unbox = TRUE)
## write(json_data, file = "mock_maintainers.json")

## -------------------------------------------------------------------------##
## -------------------------------------------------------------------------##
##    Tests adding missing using api
##     would have to manually remove from sqlite database and not run R code
##     above and grab new_rows to complete test here
## -------------------------------------------------------------------------##
## -------------------------------------------------------------------------##

## # Make sure column names are lowercase
## colnames(new_rows) <- tolower(colnames(new_rows))

## # Convert each row to a named list
## payload_list <- lapply(seq_len(nrow(new_rows)), function(i) {
##   list(
##     package = as.character(new_rows$package[i]),
##     name    = as.character(new_rows$name[i]),
##     email   = as.character(new_rows$email[i])
##   )
## })

## # Convert to JSON array
## json_payload <- toJSON(payload_list, auto_unbox = TRUE)

## # Your endpoint URL
## endpoint <- "http://127.0.0.1:4567/add-entries"

## # Make POST request
## response <- request(endpoint) %>%
##   req_headers("Content-Type" = "application/json") %>%
##   req_body_raw(json_payload) %>%
##   req_perform()

## resp_status(response)
## resp_body_string(response)

## -------------------------------------------------------------------------##
## -------------------------------------------------------------------------##
##   Tests accept policy link 
## -------------------------------------------------------------------------##
## -------------------------------------------------------------------------##

## grab this from testing the mock email validation section after changing
## database consent_date

## endpoint_url <- "http://127.0.0.1:4567/acceptpolicies/lori.shepherd@roswellpark.org/accept/9d05e78869c2bc2999f00a72096ac80ca7a28fe0"

## response <- request(endpoint_url) %>%
##   req_perform()

## resp_status(response)
## resp_body_string(response)

## Testing Endpoints

## endpoint_url = "http://127.0.0.1:4567/list/invalid/"
## response <- request(endpoint_url) %>% req_perform()

## endpoint_url = "http://127.0.0.1:4567/list/needs-consent/"
## response <- request(endpoint_url) %>% req_perform()

## endpoint_url = "http://127.0.0.1:4567/list/bademails/"
## response <- request(endpoint_url) %>% req_perform()

