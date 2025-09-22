library(dplyr)
library(stringr)


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
extract_name_email <- function(maintainer_string) {
  ## Split on commas or " and " (handle both separators)
  entries <- unlist(strsplit(maintainer_string, "\\s*,\\s*|\\s+and\\s+", perl = TRUE))
 
  ## Extract name and email using regex
  res <- str_match(entries, "^\\s*(.*?)\\s*<([^>]+)>\\s*$")
  
  ## Filter rows with valid match
  res <- res[!is.na(res[,2]) & !is.na(res[,3]), , drop = FALSE]
  
  ## Return data.frame of names and emails
  data.frame(Name = res[,2], Email = res[,3], stringsAsFactors = FALSE)
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
email_df <- unique(email_df)



## XINA  used and 
## anota2seq  used , 
## BEARscc  had /n
## XVector has special character name
## xcore has special character name
## are there other edge cases? else seems correct

write.csv(email_df, file = "MaintainerEmailList.csv", row.names=FALSE)


## Now filter only unique emails (to potentially pass to validator)

email_only <- unique(email_df[,"Email"])

temp <- lapply(email_only, write, "EmailList.txt", append=TRUE)

save.image("GetEmailList.RData")
