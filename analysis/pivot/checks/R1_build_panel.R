# R1: independent rebuild of the maintenance-pivot planning panel.
# Written from the raw cached files WITHOUT reading Maintenance_Pivot_Feasibility/R/.
# Output: panel.rds (one row per prop_id x planning date), visits.rds
suppressMessages(library(data.table))
RAW <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
OUT <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Overnight_2026-09-24/2_pivot_replication"

cs <- fread(file.path(RAW, "pipInspections_mp8v-wjtf_20260920.csv"), colClasses = "character")
m  <- fread(file.path(RAW, "pipInspectionsMaster_yg3y-7juh_20260920.csv"), colClasses = "character",
            select = c("prop_id","inspection_id","date","inspaddeddate","inspectiontype"))
st <- fread(file.path(RAW, "pipAllSites_buk3-3qpr_20260920.csv"), colClasses = "character",
            select = c("prop_id","propnum","boro"))
stopifnot(!anyDuplicated(m$inspection_id), !anyDuplicated(st$prop_id))

# --- comfort-station rows -> inspection level (any U -> U; all A -> A; else N)
cs[, r := toupper(trimws(cs_overall_condition))]           # one lowercase "u" exists
insp <- cs[, .(nU = sum(r == "U"), nA = sum(r == "A"), n = .N), by = .(inspection_id = inspectionid)]
insp <- merge(insp, m, by = "inspection_id", all.x = TRUE)
stopifnot(!anyNA(insp$prop_id))                           # many-to-one join is complete
insp <- insp[inspectiontype == "PIP"]
insp[, d := as.IDate(substr(date, 1, 10))]
insp[, e := as.IDate(substr(inspaddeddate, 1, 10))]
# Entry date missing only pre-2009; fall back to inspection date (irrelevant to 2015+ history)
insp[, e_missing := is.na(e)]
insp[is.na(e), e := d]

# --- visit = prop_id x date; entry date of a visit = latest entry among its inspections
vis <- insp[, .(nU = sum(nU), nA = sum(nA), n = sum(n), e = max(e), n_insp = .N), by = .(prop_id, d)]
vis[, rating := fifelse(nU > 0, "U", fifelse(nA == n, "A", "N"))]
setorder(vis, prop_id, d)
cat("PIP comfort-station visits:", nrow(vis), " rating table:\n"); print(table(vis$rating))

# --- planning dates
P <- as.IDate(c(sprintf("%d-%s", rep(2018:2026, each = 2), c("01-01","07-01"))))
P <- P[P <= as.IDate("2026-01-01")]
nextP <- function(p) as.IDate(ifelse(month(p) == 1, as.Date(sprintf("%d-07-01", year(p))),
                                     as.Date(sprintf("%d-01-01", year(p) + 1))))

props <- unique(vis$prop_id)
rows <- vector("list", length(P))
for (i in seq_along(P)) {
  p <- P[i]; pe <- nextP(p)
  # information set: inspected before p AND entered before p
  h  <- vis[d < p & e < p]
  hr <- h[rating != "N"]
  last_vis <- h[, .(last_d = max(d)), by = prop_id]
  h3 <- hr[d >= p - 365 * 3]
  f3 <- h3[, .(n3 = .N, u3 = sum(rating == "U")), by = prop_id]
  setorder(hr, prop_id, -d)
  l3 <- hr[, head(.SD, 3), by = prop_id][, .(nl3 = .N, ul3 = sum(rating == "U"),
                                             last_r = rating[1], last_r_d = d[1]), by = prop_id]
  lf <- hr[rating == "U", .(last_fail_d = max(d)), by = prop_id]
  x <- Reduce(function(a, b) merge(a, b, by = "prop_id", all.x = TRUE),
              list(last_vis, f3, l3, lf))
  x[is.na(n3), `:=`(n3 = 0L, u3 = 0L)]
  x[, eligible := (last_d >= p - 365 * 2) & n3 >= 1]
  # outcome: first visit in [p, pe)
  fut <- vis[d >= p & d < pe][order(prop_id, d)]
  first <- fut[, .(out_d = d[1], out_r = rating[1], n_vis_half = .N,
                   anyU_half = any(rating == "U"), lastrated_half = tail(rating[rating != "N"], 1)[1]), by = prop_id]
  x <- merge(x, first, by = "prop_id", all.x = TRUE)
  x[, P := p]
  rows[[i]] <- x
}
pan <- rbindlist(rows, fill = TRUE)
pan <- pan[eligible == TRUE]
pan[, status := fifelse(is.na(out_r), "novisit", fifelse(out_r == "N", "unrated", "rated"))]
pan[, y := fifelse(status == "rated", as.integer(out_r == "U"), NA_integer_)]
pan[, `:=`(
  last3_share = ul3 / nl3,
  smooth3 = (u3 + 0.5) / (n3 + 5),
  last_U = as.integer(last_r == "U"),
  days_since = as.numeric(P - last_d),
  days_since_fail = as.numeric(P - last_fail_d),
  half = fifelse(month(P) == 1, "H1", "H2"),
  yr = year(P)
)]
pan <- merge(pan, st, by = "prop_id", all.x = TRUE)
pan[is.na(boro) | !boro %in% c("B","M","Q","R","X"), boro := toupper(substr(prop_id, 1, 1))]
pan[is.na(propnum), propnum := sub("-.*", "", prop_id)]
pan[, stage := fifelse(yr <= 2023, "train", fifelse(yr == 2024, "select", "test"))]

cat("\nEligible site-periods by stage/status:\n")
print(dcast(pan, stage ~ status, value.var = "prop_id", fun.aggregate = length))
print(pan[status == "rated", .(rated = .N, U = sum(y)), by = stage])
print(pan[, .N, by = .(P)][order(P)])
saveRDS(vis, file.path(OUT, "visits.rds"))
saveRDS(pan, file.path(OUT, "panel.rds"))
