library(arrow)
library(dplyr)

s3_summary_url <- "s3://bioc-builddb-mirror/parquet/build_summary.parquet"
s3_info_url <- "s3://bioc-builddb-mirror/parquet/info.parquet"
s3_propagation_url <- "s3://bioc-builddb-mirror/parquet/propagation_status.parquet"




.bbs_cache <- new.env(parent = emptyenv())

get_bbs_table <- function(tblname=c("build_summary", "info",
                                    "propagation_status")){
    tblname <- match.arg(tblname)

    if (exists(tblname, envir = .bbs_cache)) {
        message(sprintf("Using cached table '%s'", tblname))
        return(get(tblname, envir = .bbs_cache))
    }  
    
    url <- paste0("s3://bioc-builddb-mirror/parquet/", tblname, ".parquet")
    message(sprintf("reading '%s' parquet file...", tblname))
    
    tbl <-
        tryCatch(
            arrow::read_parquet(url),
            error = function(e){
                warning(
                    sprintf("Could not read '%s' from remote location (%s)",
                            tblname, conditionMessage(e)),
                    call. = FALSE
                )
                return(NULL)
            })

    if (!is.null(tbl)) {
        assign(tblname, tbl, envir = .bbs_cache)
    }
  
    tbl
}


get_all_bbs_tables <- function(assign_to_global = FALSE) {
    
    table_names <- c("build_summary", "info", "propagation_status")
    tables <- list()
  
    for (tblname in table_names) {
        tbl <- get_bbs_table(tblname)
        tables[[tblname]] <- tbl
        
        if (assign_to_global && !is.null(tbl)) {
            assign(tblname, tbl, envir = .GlobalEnv)
            message(sprintf("Table '%s' assigned to global environment", tblname))
        }
    }
    
    invisible(tables)    
}





## Some initial queries to turn into functions

get_package_release_info <- function(packagename){

    stopifnot(is.character(packagename), length(packagename)==1L)
    infoTbl <- suppressMessages(get_bbs_table("info"))
    if(packagename %in% infoTbl$Package){
        infoTbl |>
            group_by(Package, git_branch) |>
            slice_max(order_by = git_last_commit_date, n = 1, with_ties = FALSE) |>
            ungroup() |> filter(Package == packagename) |>
            select(Package, Version, git_branch, git_last_commit, git_last_commit_date)
    }else{
        message(sprintf("Package: '%s' Not Found.\n  Please check spelling and capitalization",
                        packagename))
        NULL
    }
}




get_package_build_results <- function(packagename, branch="devel"){

    stopifnot(is.character(packagename), length(packagename)==1L)
    stopifnot(is.character(branch), length(branch)==1L)
    
    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))
    
    if(!(packagename %in% summaryTbl$package)){
        message(sprintf("Package: '%s' Not Found.\n  Please check spelling and capitalization",
                        packagename))
        return(NULL)
    }
    
    pkgTbl <-
        summaryTbl |> filter(package == packagename) |>
        group_by(node, version, stage) |>
        slice_max(endedat, n = 1, with_ties = FALSE) |>
        ungroup()  |> 
        select(package, node, stage, version, status, endedat)

    infoTbl <- suppressMessages(get_bbs_table("info"))
    
    if(!(branch %in% infoTbl$git_branch)){
        message(sprintf("Branch: '%s' Not Found.\n  Please check spelling and capitalization",
                        branch))
        return(NULL)
    }
        
    info_latest <-
        infoTbl |> filter(Package == packagename) |>
        group_by(Version) |>
        slice_max(git_last_commit_date, n = 1, with_ties = FALSE) |>
        ungroup() |> 
        select(Version, git_branch, git_last_commit, git_last_commit_date)
    
    if (branch == "devel"){
        info_filtered <-
            info_latest |> filter(git_branch == branch) |>
            mutate(version_obj = package_version(Version)) |>
            slice_max(version_obj, n = 1, with_ties = FALSE) |>
            select(-version_obj)
    }else{
        info_filtered <-
            info_latest |> filter(git_branch == branch)
    }
    
    results <-
        pkgTbl |>
        inner_join(info_filtered, by = c("version" = "Version"))

    return(results)
}



##
## Counts number of ERROR but should also list out of how many runs for scope
##
package_error_count <- function(packagename, builder=NULL, branch=NULL){

    stopifnot(is.character(packagename), length(packagename)==1L)
    
    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))
    
    if(!(packagename %in% summaryTbl$package)){
        message(sprintf("Package: '%s' Not Found.\n  Please check spelling and capitalization",
                        packagename))
        return(NULL)
    }

    pkgTbl <- summaryTbl |>
        filter(package == packagename, status == "ERROR")

    if (!is.null(builder)){
        pkgTbl <- pkgTbl |> filter(node %in% builder)
    }
    
    countTbl <-
        pkgTbl |>
        count(node, version, stage) |>
        mutate(
            version = factor(version, levels = as.character(sort(package_version(unique(version)))))
        ) |>
        arrange(version, node)

    infoTbl <- suppressMessages(get_bbs_table("info"))
    if (!is.null(branch)){
        branchTbl <- infoTbl |>
            filter(Package == packagename) |>
            mutate(Version = package_version(Version)) |>       
            group_by(Version) |>
            slice_max(order_by = Version, n = 1, with_ties = FALSE) |>
            ungroup() |>
            select(Version, git_branch)

        countTbl <- countTbl |>
            mutate(version = package_version(as.character(version))) |>
            left_join(branchTbl, by = c("version" = "Version")) |>
            arrange(version, node)
        countTbl <- countTbl |> filter(git_branch %in% branch)
    }
    return(countTbl)
}



## summaryTbl <- get_bbs_table("build_summary")
## library(stringr)
## summaryTbl |>
##     filter(package == "BiocFileCache", str_starts(node, "nebbiolo"), status == "ERROR") |>
##     count(node, version, stage) |> arrange(node, package_version(version))







