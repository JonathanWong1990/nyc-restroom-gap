# C6_decay_in_priority_areas.R — does the decaying / closed stock sit in the 29 priority areas?
#
# The deterioration finding (A8) is citywide. This script asks where the bad stock is:
#   (a) Parks comfort stations rated unacceptable in the latest matched window (Jan-Jun 2026,
#       the A8 window), per inspected facility, inside the 29 NTAs at ratio >= 1.5 vs elsewhere;
#   (b) Parks comfort stations under long-term closure (PIP flag, 9byw-znpj), same split;
#   (c) register restrooms that are not operational (i7jb-7jku status), same split.
# Location: PIP facilities are placed at a point on the surface of their Parks property
# (buk3-3qpr polygon); register rows use their own coordinates. NTA rule = 10_modelling_table.R
# (residential 2020 NTAs; points in park/cemetery/airport NTAs snapped to the nearest residential).
# Deterministic, no dates written. Output: outputs/decay_in_priority_areas.json
suppressMessages({library(data.table); library(sf); library(jsonlite)}); options(scipen=999)
P <- Sys.getenv("RESTROOM_PROJ", unset="."); setwd(P); dd <- "data_raw"
sf_use_s2(FALSE)

## ---- NTA rule (as 10_modelling_table.R) -------------------------------------
nta <- st_read(file.path(dd, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE)
nta <- st_transform(nta[nta$ntatype == 0, "nta2020"], 2263)
to_nta <- function(p) {
  j <- st_join(p, nta, join=st_within)
  m <- is.na(j$nta2020)
  if (any(m)) j$nta2020[m] <- nta$nta2020[st_nearest_feature(j[m, ], nta)]
  j$nta2020
}
sc <- fread(file.path(dd, "model_nta_scored_20260920.csv"))
pri <- sc[resid_ratio >= 1.5, nta2020]
stopifnot(length(pri) == 29)

## ---- Parks properties -> one point each --------------------------------------
al <- fread(file.path(dd, "pipAllSites_buk3-3qpr_20260920.csv"), showProgress=FALSE)
al <- al[!is.na(multipolygon.coordinates) & nzchar(multipolygon.coordinates)]
al <- al[!duplicated(prop_id)]
geo <- lapply(al$multipolygon.coordinates, function(s) {
  x <- fromJSON(s, simplifyVector=FALSE)
  tryCatch(st_multipolygon(lapply(x, function(poly) lapply(poly, function(ring)
    do.call(rbind, lapply(ring, function(pt) c(pt[[1]], pt[[2]])))))), error=function(e) NULL)
})
ok <- !vapply(geo, is.null, TRUE)
props <- st_sf(prop_id=al$prop_id[ok], geometry=st_sfc(geo[ok], crs=4326))
props <- st_transform(st_make_valid(props), 2263)
pts <- suppressWarnings(st_point_on_surface(props))
prop_nta <- data.table(prop_id=pts$prop_id, nta2020=to_nta(pts))
prop_nta[, priority := nta2020 %in% pri]

## ---- (a) latest-window condition, per inspected facility ---------------------
ins <- fread(file.path(dd, "pipInspections_mp8v-wjtf_20260920.csv"), showProgress=FALSE)
mas <- fread(file.path(dd, "pipInspectionsMaster_yg3y-7juh_20260920.csv"), showProgress=FALSE)
setnames(ins, "inspectionid", "inspection_id")
ins[, cs_overall_condition := toupper(trimws(cs_overall_condition))]
d <- merge(ins, mas[, .(inspection_id, prop_id, date)], by="inspection_id")
d[, date := as.IDate(date)][, yr := year(date)][, doy := as.integer(format(date, "%j"))]
w <- d[yr == 2026 & doy <= 179 & cs_overall_condition %in% c("A","U")]
w[, fac := paste(prop_id, csnumber)]
fac <- w[, .(any_u = any(cs_overall_condition == "U"), n = .N, u = sum(cs_overall_condition == "U")), by=.(fac, prop_id)]
fac <- merge(fac, prop_nta, by="prop_id", all.x=TRUE)
unplaced_a <- sum(is.na(fac$nta2020))
fac <- fac[!is.na(nta2020)]
cond <- fac[, .(facilities=.N, with_unacceptable=sum(any_u), rated=sum(n), unacceptable=sum(u)), by=priority]
cond[, `:=`(share_facilities=with_unacceptable/facilities, fail_rate=unacceptable/rated)]

## ---- (b) PIP long-term closures ----------------------------------------------
pr <- fread(file.path(dd, "pipRestrooms_9byw-znpj_20260920.csv"))
pr <- merge(pr, prop_nta, by="prop_id", all.x=TRUE)
unplaced_b <- sum(is.na(pr$nta2020)); pr <- pr[!is.na(nta2020)]
clo <- pr[, .(stations=.N, long_term_closed=sum(long_term_closure == "Yes"),
              closed_for_repairs=sum(reason_closed == "Repairs")), by=priority]
clo[, share_closed := long_term_closed/stations]

## ---- (c) register: not operational --------------------------------------------
rr <- fread(file.path(dd, "nycrestrooms_i7jb-7jku_20260920.csv"))
rr <- rr[is.finite(latitude) & is.finite(longitude)]
rp <- st_transform(st_as_sf(rr, coords=c("longitude","latitude"), crs=4326), 2263)
rr[, nta2020 := to_nta(rp)][, priority := nta2020 %in% pri]
reg <- rr[, .(restrooms=.N, not_operational=sum(status != "Operational")), by=priority]
reg[, share_not_operational := not_operational/restrooms]

o <- function(x) x[order(-priority)][, priority := ifelse(priority, "in_29", "elsewhere")][]
out <- list(
  script = "R/C6_decay_in_priority_areas.R",
  window = "Jan-Jun 2026 (doy <= 179), rated inspections only (A/U), as A8",
  priority_areas = length(pri),
  condition_2026 = o(cond), long_term_closure = o(clo), register_status = o(reg),
  unplaced = list(inspected_facilities = unplaced_a, pip_stations = unplaced_b),
  caveat = paste("A property's point decides its NTA, so a large park that straddles NTAs is counted once;",
                 "facilities in park NTAs are snapped to the nearest residential NTA (10_modelling_table rule)."))
dir.create("outputs", showWarnings=FALSE)
write_json(out, "outputs/decay_in_priority_areas.json", auto_unbox=TRUE, pretty=TRUE, digits=NA)
print(out[c("condition_2026","long_term_closure","register_status","unplaced")])
