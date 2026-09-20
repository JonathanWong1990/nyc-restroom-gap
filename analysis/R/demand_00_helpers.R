# demand_00_helpers.R -- Socrata paging helpers for the DEMAND workstream
# Follows Restroom_Rebuild/CONVENTIONS.md

options(scipen = 999)                 # RULE 1: never let R emit $offset=1e+05
suppressPackageStartupMessages({
  library(httr); library(jsonlite); library(dplyr)
})

RAW <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
STAMP <- "20260920"

# NOTE: this shells out to system curl rather than using httr::GET.
# httr drops the connection on the heavy server-side aggregation queries
# against 5wq4-mkjj (fails as a connection error well before its own
# timeout(300)), while the identical curl request returns in ~110s. curl is
# the reliable transport here, so it is what we use everywhere.
soql_get <- function(host, id, query = list(), tries = 5, maxtime = 900) {
  url <- sprintf("https://%s/resource/%s.json", host, id)
  # system2() hands args to a shell, so every one must be quoted or SoQL's
  # parentheses and spaces become shell syntax errors.
  args <- c("-s", "-S", "--fail", "--max-time", maxtime, "-G", shQuote(url))
  for (nm in names(query))
    args <- c(args, "--data-urlencode", shQuote(sprintf("%s=%s", nm, query[[nm]])))
  tmp <- tempfile(fileext = ".json"); on.exit(unlink(tmp), add = TRUE)
  for (k in seq_len(tries)) {
    rc <- suppressWarnings(system2("curl", c(args, "-o", shQuote(tmp)), stdout = TRUE, stderr = TRUE))
    st <- attr(rc, "status")
    if ((is.null(st) || st == 0) && file.exists(tmp) && file.size(tmp) > 0) {
      out <- try(fromJSON(tmp, flatten = TRUE), silent = TRUE)
      if (!inherits(out, "try-error")) return(out)
      cat("   retry", k, "( parse )\n")
    } else {
      cat("   retry", k, "( curl", if (is.null(st)) "?" else st, paste(rc, collapse = " "), ")\n")
    }
    flush.console(); Sys.sleep(5 * k)         # backoff
  }
  stop("soql_get failed: ", id)
}

# Paged pull. ALWAYS $order=:id (RULE 2) unless caller supplies its own order.
soql_page <- function(host, id, select = NULL, where = NULL, group = NULL,
                      order = ":id", page = 50000, cap = Inf) {
  acc <- list(); off <- 0
  repeat {
    q <- list(`$limit` = page, `$offset` = off, `$order` = order)
    if (!is.null(select)) q$`$select` <- select
    if (!is.null(where))  q$`$where`  <- where
    if (!is.null(group))  q$`$group`  <- group
    d <- soql_get(host, id, q)
    if (length(d) == 0 || nrow(d) == 0) break
    acc[[length(acc) + 1]] <- d
    cat("   ", id, "rows so far:", sum(sapply(acc, nrow)), "\n")
    if (nrow(d) < page) break
    off <- off + page
    if (off >= cap) break
    Sys.sleep(1.5)                    # RULE 3: be polite
  }
  if (!length(acc)) return(data.frame())
  bind_rows(lapply(acc, function(x) mutate(x, across(everything(), as.character))))
}

# Cache wrapper (RULE 4): if the file is on disk, read it, don't re-pull.
pull_cached <- function(fname, fn) {
  fp <- file.path(RAW, fname)
  if (file.exists(fp)) {
    cat("CACHED:", fname, "\n"); return(invisible(read.csv(fp, colClasses = "character")))
  }
  cat("PULLING:", fname, "\n")
  d <- fn()
  write.csv(d, fp, row.names = FALSE, na = "")
  cat("WROTE:", fname, nrow(d), "rows\n")
  invisible(d)
}
