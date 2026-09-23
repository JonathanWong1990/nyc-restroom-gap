# C2_hub_open_access.R ---------------------------------------------------------
# QUESTION: from the busiest subway station complexes, how far is the nearest
# public restroom that is actually OPEN at a given hour -- not merely listed?
#
# Scripted version of an earlier ad-hoc result that combined the team's station
# screen with our parsed hours (2026-09-23). Builds ONLY from our data_raw/:
#   mta_ak4z-sape_monthly_20260920.csv   2025 entries by station complex
#   nycrestrooms_i7jb-7jku_20260920.csv  restroom register (status, lat/lon)
#   parsed_hours_20260920.csv            R/parse_hours.R output (facility x day)
#
# DEFINITIONS (match the team's daytime station screen)
#   Station set   : station complexes with 2025 entries (monthly file is already
#                   one row per complex-month -- checked below). Drop complexes with
#                   < 1,000 entries in 2025: removes 2 Staten Island Railway stubs
#                   (St George, Tompkinsville: 1 entry each, one month) -> 424.
#   Weights       : 2025 total entries (sum of monthly ridership).
#   Hubs          : top 50 complexes by 2025 entries.
#   Point         : complex centroid from the MTA file (not entrances).
#   Distance      : STRAIGHT LINE, EPSG:2263 (ft) converted to metres. Real walking
#                   routes are typically ~1/3 longer (circuity ~1.3-1.4 in Manhattan
#                   grids), so every minute figure here is a LOWER bound.
#   Walk speed    : 72 m/min (1.2 m/s), the teammate's value.
#   "Within 500 m": nearest open restroom <= 500 m straight line.
#   Open at hour h: open_hour <= h < close_hour on that day (parsed hours).
#                   Hour 24 = midnight: open if close_hour > 24 (past-midnight
#                   close) or the facility is a 24-hour one.
#   Supply        : status == "Operational" (975 rows).
#
# HOURS SCENARIOS (the claim is bracketed, not cherry-picked)
#   641 operational rows (all NYC Parks) carry the placeholder
#   "8am-4pm, Open later seasonally" -- no real close time exists in the data.
#   off_season : placeholder = 08:00-16:00 (its literal text; winter reality).
#   in_season  : placeholder = 08:00-20:00. Justification, from the data:
#     (a) Park-type facilities that DO state explicit hours and are flagged
#         open == "Seasonal" close at median ~22:00, but they are concessions
#         (restaurants, rinks, amusement) -- an upper bound, not comfort stations.
#     (b) NYC Parks-operated (non-concession) rows with explicit hours close
#         at a median printed below (recreation centres, pools) -- also generous.
#     (c) The project's own parse_hours.R treats "dusk" as 20:00 (NYC annual
#         civil dusk); summer comfort stations are described by Parks as open
#         "later seasonally", i.e. into daylight evening, not night.
#     20:00 is therefore the most generous close we can defend for an
#     unstaffed comfort station. A sensitivity run at 22:00 (in_season_late)
#     is written to the CSV/JSON as an upper bound only.
#   24-hour facilities (8, all parkway gas stations/snack bar) : open all hours.
#   Unparseable / blank hours (18 operational)                 : treated as
#     CLOSED at every hour in the hour-specific runs (we cannot claim them
#     open); they are counted and included in the "any hours" run.
# -----------------------------------------------------------------------------

options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(dplyr); library(sf); library(ggplot2); library(jsonlite)})

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D    <- file.path(PROJ, "data_raw")
OUT  <- file.path(PROJ, "outputs"); dir.create(OUT, showWarnings = FALSE)

WALK_M_PER_MIN <- 72
FT_TO_M        <- 0.3048006096
R500           <- 500
PLACEHOLDER    <- "8am-4pm, Open later seasonally"
HOURS          <- 6:24
DAYNAMES       <- c("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")
HEAD_WEEKDAY   <- 4   # Wednesday = "typical weekday" (1 = Sunday coding in parse_hours.R)
HEAD_SAT       <- 7
SCEN <- c(off_season = 16, in_season = 20, in_season_late = 22)  # placeholder close hour

# ---- 1. Station complexes + 2025 entries -----------------------------------
m <- read.csv(file.path(D, "mta_ak4z-sape_monthly_20260920.csv"))
m25 <- m[substr(m$month, 1, 4) == "2025", ]
card <- table(table(paste(m25$month, m25$station_complex_id)))
stopifnot(identical(names(card), "1"))   # one row per complex-month: no stop-level duplication
st <- m25 |>
  group_by(station_complex_id) |>
  summarise(station_complex = first(station_complex), borough = first(borough),
            n_lat = n_distinct(latitude), lat = first(latitude), lon = first(longitude),
            entries = sum(as.numeric(ridership)), months = n_distinct(month), .groups = "drop")
stopifnot(all(st$n_lat == 1))            # one coordinate per complex
dropped <- st[st$entries < 1000, ]
cat("Complexes with 2025 data:", nrow(st), "; dropped (<1,000 entries):",
    paste(dropped$station_complex, collapse = "; "), "\n")
st <- st[st$entries >= 1000, ]
cat("Station complexes used:", nrow(st), " total 2025 entries:", format(sum(st$entries), big.mark = ","), "\n")
st <- st[order(-st$entries), ]
st$top50 <- seq_len(nrow(st)) <= 50
st_sf <- st_as_sf(st, coords = c("lon", "lat"), crs = 4326) |> st_transform(2263)

# ---- 2. Restrooms: operational + parsed hours --------------------------------
r <- read.csv(file.path(D, "nycrestrooms_i7jb-7jku_20260920.csv"))
r$facility_id <- seq_len(nrow(r))        # parse_hours.R keys on row order
ph <- read.csv(file.path(D, "parsed_hours_20260920.csv"))
stopifnot(all(ph$facility_name[ph$day_of_week == 1] == r$facility_name))   # row-key join check
op <- r[r$status == "Operational" & !is.na(r$latitude), ]
cat("Operational restrooms:", nrow(op), "\n")

ph <- ph[ph$facility_id %in% op$facility_id, ]
ph$placeholder <- ph$facility_id %in% op$facility_id[op$hours_of_operation == PLACEHOLDER]
ph$is24 <- ph$parsed & ph$is_open %in% TRUE & ph$open_hour == 0 & ph$close_hour >= 24
fac <- ph[ph$day_of_week == 1, ]
counts <- list(
  operational     = nrow(op),
  placeholder     = sum(fac$placeholder),
  open_24h        = length(unique(ph$facility_id[ph$is24 & ph$day_of_week == HEAD_WEEKDAY])),
  unparseable     = sum(!fac$parsed & fac$parse_method == "unparseable"),
  blank_hours     = sum(!fac$parsed & fac$parse_method == "blank"),
  parsed_explicit = sum(fac$parsed & !fac$placeholder))
print(unlist(counts))

# Evidence for the in-season close (printed so the justification is reproducible)
opx <- merge(ph[ph$day_of_week == HEAD_WEEKDAY & ph$parsed & !ph$placeholder & ph$is_open %in% TRUE, ],
             op[, c("facility_id", "location_type", "operator", "open")], by = "facility_id")
ev_seasonal <- median(opx$close_hour[opx$location_type == "Park" & opx$open == "Seasonal"])
ev_parks    <- median(opx$close_hour[opx$operator == "NYC Parks"])
cat(sprintf("Evidence: median close, Park-type 'Seasonal' explicit hours = %.1f (n=%d); NYC Parks-operated explicit = %.1f (n=%d)\n",
            ev_seasonal, sum(opx$location_type == "Park" & opx$open == "Seasonal"),
            ev_parks, sum(opx$operator == "NYC Parks")))

# ---- 3. Distance matrix (hubs x restrooms), metres ---------------------------
rs_sf <- st_as_sf(op, coords = c("longitude", "latitude"), crs = 4326) |> st_transform(2263)
dm <- matrix(as.numeric(st_distance(st_sf, rs_sf)), nrow = nrow(st_sf)) * FT_TO_M
colnames(dm) <- op$facility_id

open_ids <- function(h, dow, ph_close) {
  p <- ph[ph$day_of_week == dow & ph$parsed & ph$is_open %in% TRUE, ]
  p$close_hour[p$placeholder] <- ph_close
  if (h < 24) ids <- p$facility_id[p$open_hour <= h & p$close_hour > h]
  else        ids <- p$facility_id[p$close_hour > 24 | p$is24]
  unique(ids)
}

summarise_run <- function(ids) {
  cols <- colnames(dm) %in% as.character(ids)
  near <- if (any(cols)) apply(dm[, cols, drop = FALSE], 1, min) else rep(NA_real_, nrow(dm))
  mins <- near / WALK_M_PER_MIN
  t <- st$top50
  c(n_open            = sum(cols),
    all_wmean_min     = weighted.mean(mins, st$entries),
    all_median_min    = median(mins),
    all_no500_n       = sum(near > R500),
    all_no500_share   = mean(near > R500),
    top50_wmean_min   = weighted.mean(mins[t], st$entries[t]),
    top50_no500_n     = sum(near[t] > R500),
    top50_no500_share = mean(near[t] > R500))
}

# ---- 4. Daytime "any hours" reproduction ------------------------------------
repro <- summarise_run(op$facility_id)
cat(sprintf("\nREPRODUCTION (any hours, %d complexes): wmean %.2f min (target 4.29) | median %.2f (4.67) | top-50 %.2f (3.67) | top-50 >500m %d/50 (4)\n",
            nrow(st), repro["all_wmean_min"], repro["all_median_min"], repro["top50_wmean_min"], repro["top50_no500_n"]))

# ---- 5. Hour x day x scenario grid -------------------------------------------
grid <- expand.grid(hour = HOURS, dow = 1:7, scenario = names(SCEN), stringsAsFactors = FALSE)
res <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  s <- summarise_run(open_ids(g$hour, g$dow, SCEN[[g$scenario]]))
  data.frame(g, t(s))
}))
res$day <- DAYNAMES[res$dow]
res$day_type <- ifelse(res$dow %in% 2:6, "weekday", "weekend")

long <- do.call(rbind, lapply(c("n_open", "all_wmean_min", "all_median_min", "all_no500_n", "all_no500_share",
                                "top50_wmean_min", "top50_no500_n", "top50_no500_share"), function(k)
  data.frame(hour = res$hour, day = res$day, day_type = res$day_type, scenario = res$scenario,
             placeholder_close = SCEN[res$scenario], metric = k, value = round(res[[k]], 4))))
long <- rbind(long, data.frame(hour = NA, day = "any", day_type = "any", scenario = "any_hours_listed",
                               placeholder_close = NA, metric = names(repro), value = round(unname(repro), 4)))
write.csv(long, file.path(OUT, "hub_open_access.csv"), row.names = FALSE)

# ---- 6. Headlines -----------------------------------------------------------
pick <- function(h, dow, sc) {
  x <- res[res$hour == h & res$dow == dow & res$scenario == sc, ]
  list(restrooms_open = x$n_open,
       top50_entry_weighted_walk_min = round(x$top50_wmean_min, 1),
       top50_hubs_none_within_500m = x$top50_no500_n,
       all424_entry_weighted_walk_min = round(x$all_wmean_min, 1),
       all424_complexes_none_within_500m = x$all_no500_n)
}
heads <- list()
for (sc in names(SCEN)) for (d in c(HEAD_WEEKDAY, HEAD_SAT)) for (h in c(14, 18, 21))
  heads[[sc]][[DAYNAMES[d]]][[sprintf("%02d:00", h)]] <- pick(h, d, sc)
wk <- res[res$dow %in% 2:6 & res$scenario == "off_season" & res$hour %in% c(18, 21), ]
js <- list(
  script = "R/C2_hub_open_access.R", built = as.character(Sys.Date()),
  method = list(distance = "straight line, EPSG:2263; real walking routes ~1/3 longer, so minutes are lower bounds",
                walk_speed_m_per_min = WALK_M_PER_MIN, station_set = sprintf("%d MTA station complexes with 2025 entries (2 SIR stubs <1,000 entries dropped)", nrow(st)),
                weighting = "2025 total entries (ak4z-sape monthly)", hubs = "top 50 complexes by 2025 entries",
                open_rule = "open_hour <= h < close_hour, parsed hours (parse_hours.R)",
                typical_weekday = DAYNAMES[HEAD_WEEKDAY],
                scenarios = list(off_season = "placeholder '8am-4pm, Open later seasonally' closes 16:00",
                                 in_season = "placeholder closes 20:00 (dusk; see script header for justification)",
                                 in_season_late = "sensitivity only: placeholder closes 22:00 (median of explicit 'Seasonal' Park concessions)")),
  facility_counts = c(counts, list(unparseable_or_blank_treatment = "closed at every hour in hour-specific runs; included in any-hours run")),
  evidence_for_in_season_close = list(median_close_park_seasonal_explicit = ev_seasonal, median_close_nyc_parks_operated_explicit = ev_parks),
  daytime_reproduction_any_hours = list(complexes = nrow(st),
    entry_weighted_walk_min = round(repro[["all_wmean_min"]], 2), median_walk_min = round(repro[["all_median_min"]], 2),
    top50_entry_weighted_walk_min = round(repro[["top50_wmean_min"]], 2), top50_hubs_none_within_500m = repro[["top50_no500_n"]],
    teammate_targets = list(entry_weighted = 4.29, median = 4.67, top50 = 3.67, top50_none_500m = 4)),
  headline = heads,
  weekday_range_off_season_mon_fri = list(
    top50_walk_18h = round(range(wk$top50_wmean_min[wk$hour == 18]), 1),
    top50_walk_21h = round(range(wk$top50_wmean_min[wk$hour == 21]), 1)))
write_json(js, file.path(OUT, "hub_open_access.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)

cat("\nHEADLINE (", DAYNAMES[HEAD_WEEKDAY], ", top-50 hubs)\n", sep = "")
print(res[res$dow == HEAD_WEEKDAY & res$hour %in% c(14, 18, 21),
          c("scenario", "hour", "n_open", "top50_wmean_min", "top50_no500_n", "all_wmean_min", "all_no500_n")], row.names = FALSE)
cat("\nReviewer cross-check (Tuesday, off_season):\n")
print(res[res$dow == 3 & res$scenario == "off_season" & res$hour %in% c(12, 18, 21),
          c("hour", "n_open", "all_wmean_min", "top50_wmean_min", "top50_no500_n")], row.names = FALSE)

# ---- 7. Chart: top-50 walk minutes vs hour, weekday, two scenarios -----------
pd <- res[res$dow == HEAD_WEEKDAY & res$scenario %in% c("off_season", "in_season"), ]
pd$lab <- factor(ifelse(pd$scenario == "off_season", "Off-season (park toilets close 4pm)",
                        "In-season (park toilets close 8pm)"),
                 levels = c("Off-season (park toilets close 4pm)", "In-season (park toilets close 8pm)"))
cols <- c("Off-season (park toilets close 4pm)" = "#eb6834", "In-season (park toilets close 8pm)" = "#2a78d6")
lt   <- c("Off-season (park toilets close 4pm)" = "solid",   "In-season (park toilets close 8pm)" = "22")
base <- repro[["top50_wmean_min"]]
p <- ggplot(pd, aes(hour, top50_wmean_min, colour = lab, linetype = lab)) +
  geom_hline(yintercept = base, colour = "grey55", linewidth = 0.4, linetype = "dotted") +
  annotate("text", x = 9.2, y = base, label = sprintf("Any listed restroom, ignoring hours: %.1f min", base),
           hjust = 0, vjust = 1.6, size = 3.3, colour = "grey35") +
  geom_line(linewidth = 1) + geom_point(size = 1.8) +
  scale_colour_manual(values = cols, name = NULL) + scale_linetype_manual(values = lt, name = NULL) +
  scale_x_continuous(breaks = seq(6, 24, 3), labels = c("6am", "9am", "noon", "3pm", "6pm", "9pm", "12am"),
                     expand = expansion(mult = c(0.02, 0.03))) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "In the evening, the nearest open restroom moves away from NYC's busiest stations",
       subtitle = "Top 50 subway complexes, entry-weighted walk to nearest restroom open at that hour, typical weekday",
       x = NULL, y = "Walk (minutes)",
       caption = "Straight-line distance at 72 m/min; real routes ~1/3 longer. 975 operational restrooms, parsed hours.\nNYC Open Data i7jb-7jku; MTA ak4z-sape 2025 entries. R/C2_hub_open_access.R") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", legend.justification = "left", legend.key.width = unit(1.6, "lines"),
        panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        plot.title = element_text(face = "bold", size = 12.5), plot.subtitle = element_text(size = 9.5, colour = "grey30"),
        plot.caption = element_text(size = 7.8, colour = "grey40", hjust = 0),
        plot.title.position = "plot", plot.caption.position = "plot",
        plot.background = element_rect(fill = "white", colour = NA))
ggsave(file.path(OUT, "hub_open_access.png"), p, width = 7, height = 4.4, dpi = 150)
cat("\nWrote outputs/hub_open_access.{csv,json,png}\n")
