library(BiocPkgTools)
library(dplyr)
library(tidyr)
library(stringr)

##---------------------------------------------------------------------------------------------
## Get list of packages
##---------------------------------------------------------------------------------------------

urldev <- "https://www.bioconductor.org/packages/devel/data/annotation/VIEWS"
views <- read.dcf(url(urldev))
pkgs <- views[,"Package"]

##---------------------------------------------------------------------------------------------
## Get ranks from BiocPkgTools
##---------------------------------------------------------------------------------------------

results <- mapply(
  function(pkg){ message(pkg); pkgDownloadRank(pkg = pkg, pkgType = "data-annotation", version="3.22")},
  pkgs,
  SIMPLIFY = FALSE
)

download_ranks <- sapply(results, function(x) names(x)[1])
percentile <- sapply(results, function(x) as.character(x[[1]]))  # "42.66"
pkg_tbl <- data.frame(Package=pkgs, DownloadRank=download_ranks, Percentile=percentile)

##---------------------------------------------------------------------------------------------
## Get package status over the year  -- chatgpt assisted
##---------------------------------------------------------------------------------------------

get_package_yearly_stats <- function(package) {
  url <- sprintf("https://bioconductor.org/packages/stats/data-annotation/%s/%s_stats.tab", package, package)
  
  stats <- tryCatch({
    read.delim(url, stringsAsFactors = FALSE)
  }, error = function(e) {
    warning(sprintf("Could not read data for %s", package))
    return(NULL)
  })
  
  if (!is.null(stats)) {
    stats <- subset(stats, Month == "all")
    stats <- stats[order(-stats$Year), ]
    return(stats[, c("Year", "Nb_of_distinct_IPs")])
  }
  
  return(NULL)
}


# ---- Get stats for all packages ----
stats_list <- mapply(
  function(pkg) get_package_yearly_stats(pkg),
  pkg_tbl$Package,
  SIMPLIFY = FALSE
)
names(stats_list) <- pkg_tbl$Package

# ---- Convert each stats table to wide format ----
stats_wide_list <- lapply(stats_list, function(df) {
  if (is.null(df)) return(NULL)
  wide <- setNames(as.list(df$Nb_of_distinct_IPs), df$Year)
  return(wide)
})

# Convert the named list into a data frame
stats_long_df <- bind_rows(lapply(names(stats_wide_list), function(pkg) {
  data.frame(
    Package = pkg,
    Year = as.integer(names(stats_wide_list[[pkg]])),
    Nb_of_distinct_IPs = as.integer(stats_wide_list[[pkg]])
  )
}))


# Pivot to wide format
stats_wide_df <- stats_long_df %>%
  pivot_wider(names_from = Year, values_from = Nb_of_distinct_IPs, values_fill =
                                                                       NA)


##---------------------------------------------------------------------------------------------
## Combined to final table of download stats
##---------------------------------------------------------------------------------------------

final_tbl <- pkg_tbl %>%
  left_join(stats_wide_df, by = "Package")




##---------------------------------------------------------------------------------------------
## Add Linear Regression slope to indicate trend 
##---------------------------------------------------------------------------------------------

year_cols <- as.character(2009:2025)
# Function to calculate linear regression and add slope
calc_slope <- function(values) {
  years <- 2009:2025
  # Filter out NA values
  valid <- !is.na(values)
  if(sum(valid) < 2) return(NA)  # Not enough data to calculate trend
  fit <- lm(values[valid] ~ years[valid])
  coef(fit)[2]  # slope coefficient
}


tbl_full <- final_tbl %>%
    rowwise() %>%
    mutate(
        trend = calc_slope(c_across(all_of(year_cols))),
        rank_num = as.numeric(str_extract(DownloadRank, "^\\d+"))
    ) %>%
    ungroup() %>%
    arrange(rank_num) %>%
    select(-rank_num) %>%
    mutate(up_down = ifelse(trend >=0, "Upward", "Downward"))



save.image(file="AnnotationDownloadStats.RData")
write.csv(file="AnnotationDownloadStats.csv", tbl_full)



