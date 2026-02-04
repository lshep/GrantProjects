library(duckdb)
library(duckplyr)
library(stringr)

s3_summary_url <- "s3://bioc-builddb-mirror/buildResults/*-build_summary.csv.gz"
s3_info_url <- "s3://bioc-builddb-mirror/buildResults/*-info.csv.gz"
s3_propagation_url <- "s3://bioc-builddb-mirror/buildResults/*-propagation_status.csv.gz"
  
con <- dbConnect(duckdb::duckdb())

##
## These should no longer be needed as the S3 bucket we are accessing is public read
##
if (FALSE){
    dbExecute(con, "INSTALL httpfs;")
    dbExecute(con, "LOAD httpfs;")
    dbExecute(con, "CREATE OR REPLACE SECRET s3_secret (TYPE S3, PROVIDER credential_chain);")
}


## s3_url <- "s3://bioc-builddb-mirror/buildResults/0015761b48700798e7a4cc3e0d5a3e00-build_summary.csv.gz"
## result <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_url, "')", sep = ""))

##############################
##
## summary files
##
##############################

summaryFiles <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_summary_url, "')", sep = ""))


summaryFiles |>
    filter(package == "BiocFileCache", str_starts(node, "nebbiolo"), status == "ERROR") |>
    arrange(node, startedat) |>
    mutate(version_group = if_else(
               package_version(version) < package_version("3.0.0"),
               "<3",
               ">=3"
           )
           ) |>
    count(node, version_group, stage)

###############################
##
##  info files
##
###############################


infoFiles <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_info_url, "')", sep = ""))

infoFiles |>
    group_by(Package, git_branch) |>
    slice_max(order_by = git_last_commit_date, n = 1, with_ties = FALSE) |>
    ungroup() |> filter(Package == "BiocFileCache")


###############################
##
##  propagation files
##
###############################

propFiles <- dbGetQuery(con, paste("SELECT * FROM read_csv_auto('", s3_propagation_url, "')", sep = ""))



dbDisconnect(con)




## For quick reference
##
##
##
##
## > head(summaryFiles)
##        package      node    stage version status           startedat
## 1   adductData nebbiolo2 buildsrc  1.26.0     OK 2025-11-18 16:08:30
## 2   adductData nebbiolo2 checksrc  1.26.0     OK 2025-11-18 17:30:46
## 3   adductData nebbiolo2  install  1.26.0     OK 2025-11-18 15:57:47
## 4 affycompData nebbiolo2 buildsrc  1.48.0     OK 2025-11-18 16:08:30
## 5 affycompData nebbiolo2 checksrc  1.48.0     OK 2025-11-18 17:30:46
## 6 affycompData nebbiolo2  install  1.48.0     OK 2025-11-18 15:56:50
##               endedat
## 1 2025-11-18 16:08:41
## 2 2025-11-18 17:31:35
## 3 2025-11-18 15:57:56
## 4 2025-11-18 16:08:36
## 5 2025-11-18 17:31:26
## 6 2025-11-18 15:56:54
##                                                                                                                                                                                    command
## 1                                                                                            /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD build --keep-empty-dirs --no-resave-data adductData
## 2     /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD check --install=check:adductData.install-out.txt --library=/home/biocbuild/bbs-3.22-bioc/R/site-library --timings adductData_1.26.0.tar.gz
## 3                                                                                                                             /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD INSTALL adductData
## 4                                                                                          /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD build --keep-empty-dirs --no-resave-data affycompData
## 5 /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD check --install=check:affycompData.install-out.txt --library=/home/biocbuild/bbs-3.22-bioc/R/site-library --timings affycompData_1.48.0.tar.gz
## 6                                                                                                                           /home/biocbuild/bbs-3.22-bioc/R/bin/R CMD INSTALL affycompData
##                         report_md5
## 1 0015761b48700798e7a4cc3e0d5a3e00
## 2 0015761b48700798e7a4cc3e0d5a3e00
## 3 0015761b48700798e7a4cc3e0d5a3e00
## 4 0015761b48700798e7a4cc3e0d5a3e00
## 5 0015761b48700798e7a4cc3e0d5a3e00
## 6 0015761b48700798e7a4cc3e0d5a3e00
##
##
##
##
##
##
##
##
## > head(infoFiles)
##               Package Version     Maintainer               MaintainerEmail
## 1          adductData  1.26.0    Josie Hayes      jlhayes1982 at gmail.com
## 2        affycompData  1.48.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 3            affydata  1.58.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 4    Affyhgu133A2Expr  1.46.0    Zhicheng Ji               zji4 at jhu.edu
## 5     Affyhgu133aExpr  1.48.0    Zhicheng Ji               zji4 at jhu.edu
## 6 Affyhgu133Plus2Expr  1.44.0    Zhicheng Ji               zji4 at jhu.edu
##                                                     git_url   git_branch
## 1          https://git.bioconductor.org/packages/adductData RELEASE_3_22
## 2        https://git.bioconductor.org/packages/affycompData RELEASE_3_22
## 3            https://git.bioconductor.org/packages/affydata RELEASE_3_22
## 4    https://git.bioconductor.org/packages/Affyhgu133A2Expr RELEASE_3_22
## 5     https://git.bioconductor.org/packages/Affyhgu133aExpr RELEASE_3_22
## 6 https://git.bioconductor.org/packages/Affyhgu133Plus2Expr RELEASE_3_22
##   git_last_commit git_last_commit_date                       report_md5
## 1         371b0e2  2025-10-29 15:01:12 0015761b48700798e7a4cc3e0d5a3e00
## 2         45dff8f  2025-10-29 14:32:05 0015761b48700798e7a4cc3e0d5a3e00
## 3         10b07a5  2025-10-29 14:23:07 0015761b48700798e7a4cc3e0d5a3e00
## 4         3087443  2025-10-29 14:54:47 0015761b48700798e7a4cc3e0d5a3e00
## 5         404c1b6  2025-10-29 14:54:40 0015761b48700798e7a4cc3e0d5a3e00
## 6         2df08dd  2025-10-29 14:54:50 0015761b48700798e7a4cc3e0d5a3e00






## > head(prop)
##               package process                                   propagate
## 1          adductData  source UNNEEDED, same version is already published
## 2        affycompData  source UNNEEDED, same version is already published
## 3            affydata  source UNNEEDED, same version is already published
## 4    Affyhgu133A2Expr  source UNNEEDED, same version is already published
## 5     Affyhgu133aExpr  source UNNEEDED, same version is already published
## 6 Affyhgu133Plus2Expr  source UNNEEDED, same version is already published
##                         report_md5
## 1 0015761b48700798e7a4cc3e0d5a3e00
## 2 0015761b48700798e7a4cc3e0d5a3e00
## 3 0015761b48700798e7a4cc3e0d5a3e00
## 4 0015761b48700798e7a4cc3e0d5a3e00
## 5 0015761b48700798e7a4cc3e0d5a3e00
## 6 0015761b48700798e7a4cc3e0d5a3e00
