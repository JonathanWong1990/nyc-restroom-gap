# demand_02_hourprofile.R
# Station x hour-of-day x day-of-week subway ridership profile, full year.
#
# Source 5wq4-mkjj holds 44,937,246 rows. We never download them -- Socrata
# does the sum() and grouping server-side. Getting this to run took some
# experimentation; recording the findings because they are the reusable part:
#
#   * data.ny.gov enforces a hard ~60s gateway timeout. Anything slower comes
#     back as curl 52 "Empty reply from server", NOT as an HTTP error.
#   * The cost driver is THE SIZE OF THE TIME WINDOW, not the grouping.
#       - full-year window            -> 60s timeout
#       - one-month window            -> 60s timeout
#       - one-month + borough filter  -> 60s timeout
#       - ONE-WEEK + borough filter   -> ~8s. This is the workable unit.
#   * Putting a computed expression in $where (e.g. date_extract_hh(...) < 12)
#     also blows the timeout. Filter on plain indexed columns only
#     (transit_mode, borough, transit_timestamp); compute only in $select/$group.
#   * $group must repeat the full date_extract_*() expression, not the alias,
#     or you get HTTP 400 query.soql.column-not-in-group-bys.
#   * Never alias an aggregate onto its source column (sum(ridership) AS
#     ridership shadows the column). Hence AS rides / AS xfers.
#   * $order must be a plain grouped column. Ordering by the hh/dow aliases
#     forces an expensive sort and re-triggers the timeout.
#
# 52 weeks x 4 boroughs = 208 small queries. Each borough-week returns well
# under the 50,000-row page limit (Brooklyn, the largest, gives ~25.8k), so no
# $offset paging is needed -- which matters, because offset paging on an
# aggregate makes Socrata re-run the whole aggregation for every page.
# Every week is checkpointed, so a failure costs one week, not the run.

source(file.path(Sys.getenv("RESTROOM_PROJ", unset = "."), "R", "demand_00_helpers.R"))

CKPT <- file.path(RAW, "_hourprofile_parts"); dir.create(CKPT, showWarnings = FALSE)
OUT  <- file.path(RAW, sprintf("mta_5wq4-mkjj_hourprofile_%s.csv", STAMP))

SEL <- paste("station_complex_id,",
             "date_extract_hh(transit_timestamp) AS hh,",
             "date_extract_dow(transit_timestamp) AS dow,",
             "sum(ridership) AS rides, sum(transfers) AS xfers,",
             "count(*) AS n_rows")
GRP <- paste("station_complex_id, date_extract_hh(transit_timestamp),",
             "date_extract_dow(transit_timestamp)")
BOROS <- c("Bronx", "Brooklyn", "Manhattan", "Queens")   # verified: these 4 only

# 2025-09-01 is a Monday. 52 consecutive weeks -> through 2026-08-30.
weeks <- seq(as.Date("2025-09-01"), by = "week", length.out = 52)

for (i in seq_along(weeks)) {
  a <- weeks[i]; b <- a + 7
  tag <- format(a, "%Y%m%d")
  fp  <- file.path(CKPT, sprintf("wk_%s.csv", tag))
  if (file.exists(fp)) { cat("ckpt ok", tag, "\n"); flush.console(); next }

  parts <- list(); ok <- TRUE
  for (bo in BOROS) {
    d <- try(soql_page("data.ny.gov", "5wq4-mkjj", select = SEL, group = GRP,
               where = sprintf("transit_mode='subway' AND borough='%s' AND transit_timestamp >= '%s' AND transit_timestamp < '%s'", bo, a, b),
               order = "station_complex_id", page = 50000), silent = TRUE)
    if (inherits(d, "try-error")) { ok <- FALSE; cat("  FAIL", tag, bo, "\n"); break }
    if (nrow(d)) { d$borough <- bo; parts[[length(parts) + 1]] <- d }
    Sys.sleep(1)
  }
  if (!ok) next
  d <- bind_rows(parts); d$week_start <- format(a, "%Y-%m-%d")
  write.csv(d, fp, row.names = FALSE)
  cat("week", tag, nrow(d), "rows\n"); flush.console()
}

# ---- stitch: sum the 52 weeks into one station x hh x dow annual profile ----
fs <- list.files(CKPT, pattern = "^wk_.*\\.csv$", full.names = TRUE)
cat("\nstitching", length(fs), "weekly checkpoints\n")
raw <- bind_rows(lapply(fs, read.csv, colClasses = "character"))
raw <- raw |>
  mutate(across(c(hh, dow, rides, xfers, n_rows), as.numeric))

prof <- raw |>
  group_by(station_complex_id, borough, hh, dow) |>
  summarise(rides = sum(rides), xfers = sum(xfers),
            n_rows = sum(n_rows), n_weeks = n_distinct(week_start),
            .groups = "drop") |>
  arrange(station_complex_id, hh, dow)

write.csv(prof, OUT, row.names = FALSE)
cat("WROTE", basename(OUT), nrow(prof), "rows\n")
cat("stations:", n_distinct(prof$station_complex_id),
    "| hh:", n_distinct(prof$hh), "| dow:", n_distinct(prof$dow),
    "| weeks:", n_distinct(raw$week_start), "\n")
cat("total rides in profile:", format(sum(prof$rides), big.mark = ","), "\n")

# dow coding sanity check: which dow value is the weekday trough / weekend?
chk <- prof |> group_by(dow) |> summarise(rides = sum(rides)) |> arrange(dow)
cat("\nrides by dow (Socrata date_extract_dow; expect 2 adjacent low values = weekend):\n")
print(as.data.frame(chk))
cat("\nrides by hour:\n")
print(as.data.frame(prof |> group_by(hh) |> summarise(rides = sum(rides))))
