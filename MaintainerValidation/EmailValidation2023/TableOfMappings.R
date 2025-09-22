library(dplyr)
library(qdapRegex)

file1res = read.csv("resultsOfValidation/M100_all_results.csv")
file2res = read.csv("resultsOfValidation/M1525_all_results.csv")

res = rbind(file1res, file2res)[,c("Email.Address","ZB.Status")] %>%
    filter(ZB.Status == "invalid")



build_files = c(
    "https://www.bioconductor.org/packages/release/bioc/VIEWS",
    "https://www.bioconductor.org/packages/devel/bioc/VIEWS",
    "https://www.bioconductor.org/packages/release/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/devel/data/experiment/VIEWS",
    "https://www.bioconductor.org/packages/release/workflows/VIEWS",
    "https://www.bioconductor.org/packages/devel/workflows/VIEWS")

temp = read.dcf(url(build_files[1]))
pkg_email_map = temp[,c("Package", "Maintainer", "Author")]


for(i in 2:length(build_files)){
    
    temp = read.dcf(url(build_files[i]))
    pkg_email_map = rbind(pkg_email_map, temp[,c("Package", "Maintainer", "Author")])
    
}



## invalid = res[1,1]
## grep(pkg_email_map[,"Maintainer"], pattern=invalid)
## pkg_email_map[grep(pkg_email_map[,"Maintainer"], pattern=invalid),]

emails = res[,"Email.Address"]
pkgs = rep("", length(emails))
authors = rep("", length(emails))
maintainer = rep("", length(emails))

for(i in 1:length(emails)){
    invalid = emails[i]
    dx = grep(pkg_email_map[,"Maintainer"],pattern=invalid, ignore.case=TRUE)
    pkgs[i] = paste0(unique(pkg_email_map[dx,"Package"]), collapse=";")
    maintainer[i] = paste0(unique(pkg_email_map[dx,"Maintainer"]), collapse=";")
    authors[i] = paste0(unique(pkg_email_map[dx,"Author"]), collapse=";")
}


mapping = data.frame("Package"=pkgs, "Invalid"=emails, "Author"=authors)
write.table(mapping, file="mappingOfInvalid.csv", sep=",", row.names=FALSE)

mapping = data.frame("Package"=pkgs, "Invalid"=emails, "Maintainer"=maintainer, "Author"=authors)
write.table(mapping, file="mappingOfInvalidV2.csv", sep=",", row.names=FALSE)
