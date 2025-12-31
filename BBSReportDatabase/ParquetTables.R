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

    stopifnot(is.logical(assign_to_global), length(assign_to_global)==1L)
 
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
            filter(Package == packagename) |>
            group_by(git_branch) |>
            slice_max(order_by = git_last_commit_date, n = 1, with_ties = FALSE) |>
            ungroup() |>
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
    
    if(!(branch %in% infoTbl$git_branch[infoTbl$Package == packagename])){
        message(sprintf("Branch: '%s' Not Found for Package.\n  Please check spelling and capitalization",
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




## summaryTbl <- get_bbs_table("build_summary")
## library(stringr)
## summaryTbl |>
##     filter(package == "BiocFileCache", str_starts(node, "nebbiolo"), status == "ERROR") |>
##     count(node, version, stage) |> arrange(node, package_version(version))


package_error_count <- function(packagename, builder=NULL, branch=NULL){

    stopifnot(is.character(packagename), length(packagename) == 1L)
    
    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))
    
    if(!(packagename %in% summaryTbl$package)){
        message(sprintf("Package: '%s' Not Found.\n  Please check spelling and capitalization",
                        packagename))
        return(NULL)
    }

    pkgTbl <- summaryTbl |> filter(package == packagename)
    
    if (!is.null(builder)){
        pkgTbl <- pkgTbl |> filter(node %in% builder)
    }

    countTbl <- pkgTbl |>
        group_by(node, version, stage) |>
        summarise(
            count_total = n(),
            count_error = sum(status == "ERROR"),
            .groups = "drop"
        ) |>
        mutate(
            version = factor(version, levels = as.character(sort(package_version(unique(version)))))
        ) |>
        arrange(version, node)

    infoTbl <- suppressMessages(get_bbs_table("info"))
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
    
    if (!is.null(branch)){
        countTbl <- countTbl |> filter(git_branch %in% branch)
    }

    return(countTbl)
}

package_failures_over_time <- function(packagename, builder, failure_cluster_hours = 72) {

    stopifnot(is.character(packagename), length(packagename) == 1L)
    stopifnot(is.character(builder), length(builder) == 1L)
    stopifnot(is.numeric(failure_cluster_hours), length(failure_cluster_hours) == 1L)

    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))

    if (!(packagename %in% summaryTbl$package)) {
        message(sprintf("Package: '%s' Not Found.\n  Please check spelling and capitalization",
                        packagename))
        return(NULL)
    }

    if (!(builder %in% summaryTbl$node)) {
        message(sprintf("Builder: '%s' Not Found.\n  Please check spelling and capitalization",
                        builder))
        return(NULL)
    }

    pkgTbl <- summaryTbl |>
        filter(package == packagename,
               status %in% c("ERROR", "TIMEOUT"),
               node == builder) |>
        mutate(version = as.package_version(version)) |>
        arrange(startedat)   # oldest first for correct gap calculation

    if (nrow(pkgTbl) == 0) {
        message("No failing builds found for this package and builder.")
        return(NULL)
    }

    pkgEpisodes <- pkgTbl |>
        group_by(version) |>
        mutate(
            gap_hours = as.numeric(difftime(startedat, lag(startedat), units = "hours")),
            gap_days  = as.numeric(difftime(as.Date(startedat), lag(as.Date(startedat)), units = "days")),
            episode = cumsum(is.na(gap_hours) | (gap_hours > failure_cluster_hours & gap_days > 1))
        ) |>
        ungroup()

    episodeSummary <- pkgEpisodes |>
        group_by(version, episode) |>
        summarise(
            first_failure = min(startedat),
            last_failure  = max(startedat),
            n_failures    = n(),
            stages        = paste(sort(unique(stage)), collapse = ", "),
            statuses      = paste(sort(unique(status)), collapse = ", "),
            .groups = "drop"
        ) |>
        arrange(desc(first_failure))

    
    return(episodeSummary)
}


get_latest_branches <- function(infoTbl=NULL) {

    if(is.null(infoTbl)) infoTbl <- suppressMessages(get_bbs_table("info"))

    stopifnot("git_branch" %in% names(infoTbl))
      
    release_branches <- grep("^RELEASE", infoTbl$git_branch, value = TRUE)
    if (length(release_branches) > 0) {
        release_versions <- as.numeric(gsub("RELEASE_(\\d+)_(\\d+)", "\\1\\2", release_branches))
        latest_release <- release_branches[which.max(release_versions)]
    } else {
        latest_release <- character(0)
    }
    
    c("devel", latest_release)
}


## will be mix of type as there is nothing in these that distinguish between
## software/workflow etc....

get_build_report <- function(build_date = Sys.Date(), branch = NULL, builder = NULL) {

    stopifnot(inherits(build_date, c("Date", "character")))
  
    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))
    infoTbl <- suppressMessages(get_bbs_table("info"))
    
    build_date <- as.Date(build_date)
    
    dailyTbl <- summaryTbl |> 
        filter(as.Date(startedat) == build_date)
    
    if (nrow(dailyTbl) == 0) {
        message("No builds found on this date.")
        return(NULL)
    }
  
    if (is.null(branch)) {
        branch_filter <- get_latest_branches(infoTbl)
    } else {
        branch_filter <- branch
    }
  
    info_filtered <- infoTbl |> 
        filter(git_branch %in% branch_filter) |> 
        group_by(Package, git_branch) |> 
        slice_max(package_version(Version), n = 1, with_ties = FALSE) |> 
        ungroup() |> 
        select(Package, Version, git_branch, git_last_commit, git_last_commit_date)
  
    daily_report <- dailyTbl |> 
        inner_join(info_filtered, by = c("package" = "Package", "version" = "Version"))
  
    if (!is.null(builder)) {
        daily_report <- daily_report |> filter(node == builder)
        if (nrow(daily_report) == 0) {
            message(sprintf("No builds found for builder '%s' on %s.", builder, build_date))
            return(NULL)
        }
    }
    stage_levels <- c("install", "buildsrc", "checksrc")
    
    daily_report <- daily_report |> 
        mutate(stage = factor(stage, levels = stage_levels),
               version = package_version(version)) |> 
        arrange(git_branch, package, version, node, stage)
    
    daily_report
}

get_failing_packages <- function(branch = NULL, builder = NULL) {

    summaryTbl <- suppressMessages(get_bbs_table("build_summary"))
    infoTbl <- suppressMessages(get_bbs_table("info"))
  
    if (is.null(branch)) {
        branch_filter <- get_latest_branches(infoTbl)
    } else {
        branch_filter <- branch
    }
  
    info_filtered <- infoTbl |> 
        filter(git_branch %in% branch_filter) |> 
        group_by(Package, git_branch) |> 
        slice_max(package_version(Version), n = 1, with_ties = FALSE) |> 
        ungroup() |> 
        select(Package, Version, git_branch)
  
    failures <- summaryTbl |> 
        filter(status %in% c("ERROR", "TIMEOUT")) |> 
        inner_join(info_filtered,
                   by = c("package" = "Package", "version" = "Version"),
                   relationship = "many-to-many")
  
    if (!is.null(builder)) {
        failures <- failures |> filter(node %in% builder)
    }
  
    if (nrow(failures) == 0) {
        message("No failing packages found for the specified branch(es) and node(s).")
        return(NULL)
    }
    

    failures |> 
        mutate(version = package_version(version)) |>
        group_by(git_branch, package, version, node) |> 
        summarise(
            stages   = paste(sort(unique(stage)), collapse = ", "),
            statuses = paste(sort(unique(status)), collapse = ", "),
            .groups  = "drop"
        ) |> 
        arrange(git_branch, package, version, node)


}
