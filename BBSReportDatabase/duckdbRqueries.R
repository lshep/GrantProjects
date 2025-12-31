library(duckdb)
library(DBI)
library(duckplyr)

con <- dbConnect(duckdb(), dbdir = "bioc_builddb.duckdb")

tblnames <- dbListTables(con)

for(tbl in tblnames){
    cat("\n----------------\n")
    message(tbl, ":\n")
    df <- dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 6", tbl))
    print(df)
    cat("\n----------------\n")
}




## ----------------
## build_overview:

##     package version                       report_md5   git_branch
## 1   peacoqc  1.17.0 1c6513b0a93207018976ff2f6550a1fc        devel
## 2  proactiv  1.17.0 1c6513b0a93207018976ff2f6550a1fc        devel
## 3       cdi   1.0.2 2bfa8c8fc0fffa5c4345303405ebfd79 RELEASE_3_18
## 4    chipqc  1.38.0 2bfa8c8fc0fffa5c4345303405ebfd79 RELEASE_3_18
## 5 contibait  1.30.0 2bfa8c8fc0fffa5c4345303405ebfd79 RELEASE_3_18
## 6   degnorm  1.12.0 2bfa8c8fc0fffa5c4345303405ebfd79 RELEASE_3_18
##   git_last_commit all_stages_ok n_stages       build_started
## 1         3449ab9          TRUE        4 2025-03-18 19:09:20
## 2         f0775da          TRUE        4 2025-03-18 19:19:29
## 3         38c9ab6          TRUE        4 2024-03-05 20:47:58
## 4         850e458         FALSE        4 2024-03-05 20:33:58
## 5         4d4e432         FALSE        4 2024-03-05 20:32:33
## 6         405e5cb          TRUE        4 2024-03-05 20:44:08
##        build_finished
## 1 2025-03-19 12:57:28
## 2 2025-03-19 13:03:28
## 3 2024-03-06 13:24:25
## 4 2024-03-06 13:26:32
## 5 2024-03-06 13:30:32
## 6 2024-03-06 13:33:16
##                                                                 processes
## 1 mac.binary.big-sur-x86_64, win.binary, source, mac.binary.big-sur-arm64
## 2 mac.binary.big-sur-x86_64, source, mac.binary.big-sur-arm64, win.binary
## 3                                                      win.binary, source
## 4                                                      win.binary, source
## 5                                                      win.binary, source
## 6                                                      win.binary, source

## ----------------

## ----------------
## build_stage_detail:

##   package version      node    stage status           startedat
## 1   omadb  2.23.0  kunpeng2  install     OK 2025-03-18 19:57:04
## 2   omadb  2.23.0   lconway buildbin     OK 2025-03-19 05:21:19
## 3   omadb  2.23.0   lconway buildsrc     OK 2025-03-18 21:52:50
## 4   omadb  2.23.0   lconway checksrc     OK 2025-03-19 02:34:30
## 5   omadb  2.23.0   lconway  install     OK 2025-03-18 19:32:33
## 6   omadb  2.23.0 nebbiolo1 buildsrc     OK 2025-03-18 22:26:56
##               endedat git_branch git_last_commit                  process
## 1 2025-03-18 19:57:28      devel         c8dc611 mac.binary.big-sur-arm64
## 2 2025-03-19 05:21:44      devel         c8dc611 mac.binary.big-sur-arm64
## 3 2025-03-18 21:53:25      devel         c8dc611 mac.binary.big-sur-arm64
## 4 2025-03-19 02:42:59      devel         c8dc611 mac.binary.big-sur-arm64
## 5 2025-03-18 19:32:56      devel         c8dc611 mac.binary.big-sur-arm64
## 6 2025-03-18 22:27:19      devel         c8dc611 mac.binary.big-sur-arm64
##                                     propagate                       report_md5
## 1 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc
## 2 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc
## 3 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc
## 4 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc
## 5 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc
## 6 UNNEEDED, same version is already published 1c6513b0a93207018976ff2f6550a1fc

## ----------------

## ----------------
## info_t:

##               package version     Maintainer               MaintainerEmail
## 1          adductdata  1.26.0    Josie Hayes      jlhayes1982 at gmail.com
## 2        affycompdata  1.48.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 3            affydata  1.58.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 4    affyhgu133a2expr  1.46.0    Zhicheng Ji               zji4 at jhu.edu
## 5     affyhgu133aexpr  1.48.0    Zhicheng Ji               zji4 at jhu.edu
## 6 affyhgu133plus2expr  1.44.0    Zhicheng Ji               zji4 at jhu.edu
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

## ----------------

## ----------------
## info_v:

##               package version     Maintainer               MaintainerEmail
## 1          adductdata  1.26.0    Josie Hayes      jlhayes1982 at gmail.com
## 2        affycompdata  1.48.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 3            affydata  1.58.0 Robert D Shear rshear at ds.dfci.harvard.edu
## 4    affyhgu133a2expr  1.46.0    Zhicheng Ji               zji4 at jhu.edu
## 5     affyhgu133aexpr  1.48.0    Zhicheng Ji               zji4 at jhu.edu
## 6 affyhgu133plus2expr  1.44.0    Zhicheng Ji               zji4 at jhu.edu
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

## ----------------

## ----------------
## latest_build_per_package:

##               package version                       report_md5   git_branch
## 1              qvalue  2.43.0 fdfdaa0221bb792c7e9c05356571ab96        devel
## 2            rbowtie2  2.17.0 fdfdaa0221bb792c7e9c05356571ab96        devel
## 3               ripat  1.14.0 e8041b1bd746d1919d694caf65774861 RELEASE_3_19
## 4               rolde  1.15.0 fdfdaa0221bb792c7e9c05356571ab96        devel
## 5 signaturesearchdata  1.25.0 6473936f316e66435b3c258f06bc12ff        devel
## 6            stringdb  2.23.0 fdfdaa0221bb792c7e9c05356571ab96        devel
##   git_last_commit all_stages_ok n_stages       build_started
## 1         b7507f6          TRUE        4 2025-12-29 20:04:57
## 2         037bb32          TRUE        4 2025-12-29 20:09:18
## 3         f2a161d         FALSE        4 2024-10-16 20:42:07
## 4         30dfeba          TRUE        4 2025-12-29 20:12:45
## 5         ee7e356          TRUE        3 2025-12-30 15:57:09
## 6         d94568c          TRUE        4 2025-12-29 20:06:48
##        build_finished
## 1 2025-12-30 07:50:53
## 2 2025-12-30 07:55:18
## 3 2024-10-19 00:21:37
## 4 2025-12-30 08:18:27
## 5 2025-12-30 18:04:01
## 6 2025-12-30 09:33:32
##                                                         processes
## 1                                source, mac.binary.big-sur-arm64
## 2                                source, mac.binary.big-sur-arm64
## 3 mac.binary.big-sur-arm64, mac.binary.big-sur-x86_64, win.binary
## 4                                source, mac.binary.big-sur-arm64
## 5                                                          source
## 6                                source, mac.binary.big-sur-arm64

## ----------------

## ----------------
## propagation_t:

##               package process                                   propagate
## 1          adductdata  source UNNEEDED, same version is already published
## 2        affycompdata  source UNNEEDED, same version is already published
## 3            affydata  source UNNEEDED, same version is already published
## 4    affyhgu133a2expr  source UNNEEDED, same version is already published
## 5     affyhgu133aexpr  source UNNEEDED, same version is already published
## 6 affyhgu133plus2expr  source UNNEEDED, same version is already published
##                         report_md5
## 1 0015761b48700798e7a4cc3e0d5a3e00
## 2 0015761b48700798e7a4cc3e0d5a3e00
## 3 0015761b48700798e7a4cc3e0d5a3e00
## 4 0015761b48700798e7a4cc3e0d5a3e00
## 5 0015761b48700798e7a4cc3e0d5a3e00
## 6 0015761b48700798e7a4cc3e0d5a3e00

## ----------------

## ----------------
## propagation_v:

##               package process                                   propagate
## 1          adductdata  source UNNEEDED, same version is already published
## 2        affycompdata  source UNNEEDED, same version is already published
## 3            affydata  source UNNEEDED, same version is already published
## 4    affyhgu133a2expr  source UNNEEDED, same version is already published
## 5     affyhgu133aexpr  source UNNEEDED, same version is already published
## 6 affyhgu133plus2expr  source UNNEEDED, same version is already published
##                         report_md5
## 1 0015761b48700798e7a4cc3e0d5a3e00
## 2 0015761b48700798e7a4cc3e0d5a3e00
## 3 0015761b48700798e7a4cc3e0d5a3e00
## 4 0015761b48700798e7a4cc3e0d5a3e00
## 5 0015761b48700798e7a4cc3e0d5a3e00
## 6 0015761b48700798e7a4cc3e0d5a3e00

## ----------------

## ----------------
## summary_t:

##        package version      node    stage status           startedat
## 1   adductdata  1.26.0 nebbiolo2 buildsrc     OK 2025-11-18 16:08:30
## 2   adductdata  1.26.0 nebbiolo2 checksrc     OK 2025-11-18 17:30:46
## 3   adductdata  1.26.0 nebbiolo2  install     OK 2025-11-18 15:57:47
## 4 affycompdata  1.48.0 nebbiolo2 buildsrc     OK 2025-11-18 16:08:30
## 5 affycompdata  1.48.0 nebbiolo2 checksrc     OK 2025-11-18 17:30:46
## 6 affycompdata  1.48.0 nebbiolo2  install     OK 2025-11-18 15:56:50
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

## ----------------

## ----------------
## summary_v:

##        package version      node    stage status           startedat
## 1   adductdata  1.26.0 nebbiolo2 buildsrc     OK 2025-11-18 16:08:30
## 2   adductdata  1.26.0 nebbiolo2 checksrc     OK 2025-11-18 17:30:46
## 3   adductdata  1.26.0 nebbiolo2  install     OK 2025-11-18 15:57:47
## 4 affycompdata  1.48.0 nebbiolo2 buildsrc     OK 2025-11-18 16:08:30
## 5 affycompdata  1.48.0 nebbiolo2 checksrc     OK 2025-11-18 17:30:46
## 6 affycompdata  1.48.0 nebbiolo2  install     OK 2025-11-18 15:56:50
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

## ----------------






dbGetQuery(con, "
SELECT package, version
FROM latest_build_per_package
WHERE NOT all_stages_ok
")



dbDisconnect(con, shutdown = TRUE)
