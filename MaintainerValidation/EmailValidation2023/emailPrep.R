library(dplyr)
library(qdapRegex)

files = c(
    "https://www.bioconductor.org/packages/release/bioc/VIEWS",
    "https://www.bioconductor.org/packages/devel/bioc/VIEWS",
    "https://www.bioconductor.org/packages/release/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/devel/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/release/workflows/VIEWS",
    "https://www.bioconductor.org/packages/devel/workflows/VIEWS")


emails = ""

for(i in files){
    temp = read.dcf(url(i))
    emails = c(emails, unlist(ex_email(temp[,"Maintainer"])))

}
emails = tolower(emails)
emailsUnique = unique(emails)
emailsUnique = emailsUnique[!is.na(emailsUnique)]
emailsUnique = emailsUnique[-1]

## > length(emailsUnique)
## [1] 1625

## crosscheck which(is.na(match(emails, emailsUnique)))

lapply(emailsUnique, write, "MaintainerEmailList.txt", append=TRUE)
