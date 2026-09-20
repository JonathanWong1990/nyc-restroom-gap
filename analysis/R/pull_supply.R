# pull_supply.R -- SUPPLY side pull for NYC Restroom Gap & ROI rebuild
options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(httr); library(jsonlite); library(dplyr)})

BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
RAW  <- file.path(BASE, "data_raw")
STAMP <- format(Sys.Date(), "%Y%m%d")
dir.create(RAW, showWarnings = FALSE, recursive = TRUE)

soda_get <- function(id, domain = "data.cityofnewyork.us", page = 25000, select = NULL) {
  url <- sprintf("https://%s/resource/%s.json", domain, id)
  out <- list(); off <- 0
  repeat {
    q <- list(`$limit` = page, `$offset` = off, `$order` = ":id")
    if (!is.null(select)) q$`$select` <- select
    r <- NULL
    for (try_i in 1:4) {
      r <- try(GET(url, query = q, timeout(180)), silent = TRUE)
      if (!inherits(r, "try-error") && status_code(r) == 200) break
      Sys.sleep(2 * try_i); r <- NULL
    }
    if (is.null(r)) stop("failed at offset ", off, " for ", id)
    d <- fromJSON(content(r, "text", encoding = "UTF-8"), flatten = TRUE)
    if (length(d) == 0 || nrow(d) == 0) break
    out[[length(out) + 1]] <- d
    cat(sprintf("  %s: +%d rows (offset %d)\n", id, nrow(d), off))
    if (nrow(d) < page) break
    off <- off + page; Sys.sleep(1.5)
  }
  bind_rows(out)
}

pull_cached <- function(label, id, domain = "data.cityofnewyork.us", select = NULL) {
  f <- file.path(RAW, sprintf("%s_%s_%s.csv", label, id, STAMP))
  old <- list.files(RAW, pattern = sprintf("^%s_%s_.*\\.csv$", label, id), full.names = TRUE)
  if (length(old)) { cat("CACHED:", basename(old[1]), "\n"); return(read.csv(old[1])) }
  cat("PULLING", label, id, "\n")
  d <- soda_get(id, domain, select = select)
  # serialize list-columns (e.g. multipolygon geometry) to JSON text so CSV works
  for (nm in names(d)) if (is.list(d[[nm]])) d[[nm]] <- vapply(d[[nm]], function(x)
      if (is.null(x) || length(x) == 0) NA_character_ else as.character(toJSON(x, auto_unbox = TRUE)), character(1))
  write.csv(d, f, row.names = FALSE, na = "")
  cat("  saved", basename(f), nrow(d), "rows x", ncol(d), "cols\n")
  d
}

restrooms  <- pull_cached("nycrestrooms",   "i7jb-7jku")
parks      <- pull_cached("parksprops",     "enfh-gkve")
capital    <- pull_cached("capitaltracker", "4hcv-tc5r")
csclosure  <- pull_cached("csclosurecovid", "i5n2-q8ck")
pipclosure <- pull_cached("pipRestrooms",   "9byw-znpj")
structures <- pull_cached("parkstructures", "n8q6-i44s")
pipinsp    <- pull_cached("pipInspections", "mp8v-wjtf")
pipsites   <- pull_cached("pipAllSites",    "buk3-3qpr")
pipmaster  <- pull_cached("pipInspectionsMaster", "yg3y-7juh")

# Parks Properties geometry: the JSON API returns the multipolygon flattened and
# empty, so geometry must come from the GeoJSON export endpoint instead.
gj <- file.path(RAW, sprintf("parksprops_enfh-gkve_%s.geojson", STAMP))
if (!file.exists(gj))
  download.file("https://data.cityofnewyork.us/api/geospatial/enfh-gkve?method=export&format=GeoJSON", gj, quiet = TRUE)

cat("\nDONE\n")
