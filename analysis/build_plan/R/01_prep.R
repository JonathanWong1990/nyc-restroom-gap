# 01_prep.R -- PROTOTYPE coverage-based siting plan: build demand points, supply, candidates.
# Reads ../../Restroom_Rebuild/data_raw, ../../Pedestrian_Demand_Test/data, ../../Restroom_Rebuild/outputs
# (all READ-ONLY). Writes only Build_Plan/prototype/cache/prep.rds.
#
# DEFINITIONS (see README.md)
#   Service standard : demand point covered if an OPEN restroom within 500 m straight line (EPSG:2263 ft).
#   Hour logic       : copied from Restroom_Rebuild/R/C2_hub_open_access.R (Wednesday, dow = 4);
#                      placeholder "8am-4pm, Open later seasonally" close = 16 (off) / 20 (in-season).
#   Demand objectives (separate, never summed):
#     residents  2020-24 ACS tract population, spread evenly over a 150 m grid of points inside the tract
#                (points inside Parks properties dropped; tract point-on-surface if no grid point survives)
#     workers    LODES WAC 2023 C000 jobs (block codes -> tract), spread over the same points
#     subway     2025 entries by MTA station complex (as C2: 424 complexes, <1,000 entries dropped)
#     streets    DOT fwpa-qxaf Global + Regional segments, sampled every 50 m, weight = metres of street
#   Candidates : 150 m grid points inside eligible Parks properties or DOT plazas, grid points within 30 m of a
#                Global/Regional segment, points every 150 m along those segments, and one point per plaza.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(data.table); library(jsonlite)})
sf_use_s2(FALSE)

BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
D    <- file.path(BASE, "Restroom_Rebuild/data_raw")
PED  <- file.path(BASE, "Pedestrian_Demand_Test/data/dotpedmob_fwpa-qxaf_20260925_dedup.geojson")
PT   <- file.path(BASE, "Build_Plan/prototype")
FT   <- 0.3048006096                       # metres per US survey foot
M2FT <- function(m) m / FT
PLACEHOLDER <- "8am-4pm, Open later seasonally"
WED <- 4
GRID_M <- 150
t0 <- Sys.time()

# ---- 1. Geography --------------------------------------------------------------------------
tr <- st_read(file.path(D, "nycopendata_63ge-mke6_tracts2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
stopifnot(nrow(tr) == 2325, !anyDuplicated(tr$geoid))
nta <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
stopifnot(nrow(nta) == 262, !anyDuplicated(nta$nta2020))
parks_all <- readRDS(file.path(D, "parksprops_sf_20260920.rds")) |> st_transform(2263) |> st_make_valid()
# Parks land eligible for a new unit: exclude land where a public restroom makes no sense
EXCL_PARK <- c("Cemetery", "Parkway", "Undeveloped", "Operations", "Lot")
parks_ok <- parks_all[!parks_all$typecategory %in% EXCL_PARK, ]
plz <- st_read(file.path(D, "nycdot_k5k6-6jex_plazas_polygon_20260923.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
cat("parks props:", nrow(parks_all), " eligible:", nrow(parks_ok), " plazas:", nrow(plz), "\n")

# ---- 2. Demand: residents + workers on a 150 m grid ------------------------------------------
acs <- fread(file.path(D, "census_acs5_2024_tract_demographics_20260920.csv"), colClasses = c(geoid = "character"))
stopifnot(!anyDuplicated(acs$geoid), sum(acs$pop_total) == 8483844)
miss <- setdiff(acs$geoid, tr$geoid)
stopifnot(sum(acs$pop_total[acs$geoid %in% miss]) == 0)          # the 2 non-matching tracts are pop 0 (water)
wac <- fread(file.path(D, "census_lodes8_nywac2023_20260920.csv"), select = c("w_geocode", "C000", "tract"),
             colClasses = c(w_geocode = "character", tract = "character"))
stopifnot(all(nchar(wac$w_geocode) == 15), !anyDuplicated(wac$w_geocode),        # block-level, one row per block
          all(substr(wac$w_geocode, 1, 11) == wac$tract))
jobs_tr <- wac[, .(jobs = sum(C000)), by = tract]
stopifnot(all(jobs_tr$tract %in% tr$geoid))
cat("LODES: blocks", nrow(wac), "-> tracts", nrow(jobs_tr), "; jobs", sum(jobs_tr$jobs), "\n")

tr <- tr |> left_join(acs[, .(geoid, pop = pop_total)], by = "geoid") |>
  left_join(as.data.frame(jobs_tr), by = c("geoid" = "tract"))
tr$pop[is.na(tr$pop)] <- 0; tr$jobs[is.na(tr$jobs)] <- 0
stopifnot(sum(tr$pop) == 8483844, sum(tr$jobs) == sum(wac$C000))

grid_pts <- function(poly, cell_m, offset_m = 0) {
  bb <- st_bbox(poly)
  st_make_grid(poly, cellsize = M2FT(cell_m), what = "centers",
               offset = c(bb[["xmin"]] - M2FT(offset_m), bb[["ymin"]] - M2FT(offset_m)))
}
city <- st_union(tr)
g <- grid_pts(city, GRID_M)
g <- st_sf(geometry = g)
g <- st_join(g, tr[, c("geoid")], join = st_intersects, left = FALSE)
g <- g[!duplicated(st_coordinates(g)), ]                       # a point on a shared edge joins twice
in_park <- lengths(st_intersects(g, parks_all)) > 0
g <- g[!in_park, ]
cat("residential/worker grid points (outside parks):", nrow(g), "\n")
fallback <- tr[!tr$geoid %in% g$geoid & (tr$pop > 0 | tr$jobs > 0), "geoid"]
fb <- st_sf(geoid = fallback$geoid, geometry = st_point_on_surface(st_geometry(fallback)))
cat("tracts with no grid point outside parks (use point-on-surface):", nrow(fb), "\n")
dg <- rbind(g, fb)
npt <- table(dg$geoid)
dg$pop  <- tr$pop[match(dg$geoid, tr$geoid)]  / as.numeric(npt[dg$geoid])
dg$jobs <- tr$jobs[match(dg$geoid, tr$geoid)] / as.numeric(npt[dg$geoid])
stopifnot(abs(sum(dg$pop) - 8483844) < 1e-3, abs(sum(dg$jobs) - sum(wac$C000)) < 1e-3)

# ---- 3. Demand: subway complexes (as C2) ------------------------------------------------------
m <- fread(file.path(D, "mta_ak4z-sape_monthly_20260920.csv"))
m25 <- m[substr(month, 1, 4) == "2025"]
stopifnot(!anyDuplicated(m25[, .(month, station_complex_id)]))
st <- m25[, .(station_complex = first(station_complex), n_lat = uniqueN(latitude), lat = first(latitude),
              lon = first(longitude), entries = sum(as.numeric(ridership))), by = station_complex_id]
stopifnot(all(st$n_lat == 1))
st <- st[entries >= 1000]
stopifnot(nrow(st) == 424)
sub <- st_as_sf(as.data.frame(st), coords = c("lon", "lat"), crs = 4326) |> st_transform(2263)
cat("subway complexes:", nrow(sub), " entries:", format(sum(sub$entries), big.mark = ","), "\n")

# ---- 4. Demand: busy streets (Global + Regional) ---------------------------------------------
seg <- st_read(PED, quiet = TRUE) |> st_transform(2263)
seg <- seg[as.numeric(seg$rank) <= 2, ]
seg <- seg[!duplicated(sf::st_as_text(sf::st_geometry(seg))), ]   # one row per physical street: DOT file repeats segments (number check 25 Sep); was 1918 rows
stopifnot(!anyDuplicated(sf::st_as_text(sf::st_geometry(seg))))
segl <- suppressWarnings(st_cast(seg[, c("segmentid", "street", "category", "nta2020")], "LINESTRING"))
segl$len_m <- as.numeric(st_length(segl)) * FT
n_s <- pmax(1, ceiling(segl$len_m / 50))
sp <- st_line_sample(st_geometry(segl), n = n_s, type = "regular")
sp_n <- sapply(sp, function(x) nrow(st_coordinates(x)))
stopifnot(all(sp_n == n_s))
spts <- suppressWarnings(st_cast(st_sf(len_m = segl$len_m / n_s, category = segl$category, geometry = sp), "POINT"))
stopifnot(nrow(spts) == sum(n_s), abs(sum(spts$len_m) - sum(segl$len_m)) < 1e-6)
cat("busy-street sample points:", nrow(spts), " street km:", round(sum(segl$len_m) / 1000, 1), "\n")

demand <- list(
  residents = list(pts = st_geometry(dg),   w = dg$pop,          unit = "residents"),
  workers   = list(pts = st_geometry(dg),   w = dg$jobs,         unit = "jobs"),
  subway    = list(pts = st_geometry(sub),  w = sub$entries,     unit = "2025 subway entries"),
  streets   = list(pts = st_geometry(spts), w = spts$len_m,      unit = "metres of Global/Regional street"))

# ---- 5. Candidate new sites ------------------------------------------------------------------
cg <- st_sf(geometry = grid_pts(city, GRID_M, offset_m = GRID_M / 2))       # offset from demand grid
cg <- cg[lengths(st_intersects(cg, city)) > 0, ]
c_park  <- lengths(st_intersects(cg, parks_ok)) > 0
c_plaza <- lengths(st_intersects(cg, plz)) > 0
c_street <- lengths(st_is_within_distance(cg, seg, dist = M2FT(30))) > 0
cand_grid <- cg[c_park | c_plaza | c_street, ]
cand_grid$type <- ifelse(c_plaza, "plaza", ifelse(c_street, "busy_street", "park"))[c_park | c_plaza | c_street]
# busy-street frontage points every 150 m along segments (grid alone misses most thin street corridors)
n_c <- pmax(1, round(segl$len_m / GRID_M))
cs <- suppressWarnings(st_cast(st_sf(type = "busy_street",
        geometry = st_line_sample(st_geometry(segl), n = n_c, type = "regular")), "POINT"))
cp <- st_sf(type = "plaza", geometry = st_point_on_surface(st_geometry(plz)))
cand <- rbind(cand_grid, cs, cp)
# drop near-duplicates (< 25 m apart), keeping the first
nb <- st_is_within_distance(cand, cand, dist = M2FT(25))
keep <- rep(TRUE, nrow(cand))
for (i in seq_len(nrow(cand))) if (keep[i]) { o <- setdiff(nb[[i]], i); keep[o[o > i]] <- FALSE }
cand <- cand[keep, ]
cand$cand_id <- seq_len(nrow(cand))
cat("candidates:", nrow(cand), "\n"); print(table(cand$type))

# ---- 6. Supply: register + hours + closure/failing flags --------------------------------------
r <- read.csv(file.path(D, "nycrestrooms_i7jb-7jku_20260920.csv"))
r$facility_id <- seq_len(nrow(r))
ph <- read.csv(file.path(D, "parsed_hours_20260920.csv"))
stopifnot(all(ph$facility_name[ph$day_of_week == 1] == r$facility_name))
stopifnot(sum(r$status == "Operational" & !is.na(r$latitude)) == 975)
phw <- ph[ph$day_of_week == WED, ]
stopifnot(nrow(phw) == nrow(r), all(phw$facility_id == r$facility_id))
r$w_open  <- phw$open_hour;  r$w_close <- phw$close_hour
r$w_ok    <- phw$parsed & phw$is_open %in% TRUE
r$placeholder <- r$hours_of_operation %in% PLACEHOLDER
rr <- r[!is.na(r$latitude), ]
rs <- st_as_sf(rr, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |> st_transform(2263)

# PIP property polygons (same parse as Internal_Reviews/pivot_review_2026-09-24_files/m.R)
pr <- fread(file.path(D, "pipRestrooms_9byw-znpj_20260920.csv"))
stopifnot(nrow(pr) == 736, sum(pr$long_term_closure == "Yes") == 80)
ins <- fread(file.path(D, "pipInspections_mp8v-wjtf_20260920.csv"))
mas <- fread(file.path(D, "pipInspectionsMaster_yg3y-7juh_20260920.csv"),
             select = c("prop_id", "inspection_id", "date"))
stopifnot(!anyDuplicated(mas$inspection_id))
ins[, cs_overall_condition := toupper(trimws(cs_overall_condition))]
ii <- merge(ins, mas, by.x = "inspectionid", by.y = "inspection_id")
stopifnot(nrow(ii) == nrow(ins))
ii <- ii[as.IDate(date) >= as.IDate("2025-01-01") & cs_overall_condition %in% c("A", "U")]
fail <- ii[, .(n_rated = .N, n_u = sum(cs_overall_condition == "U")), by = prop_id]
fail <- fail[n_u >= 2 & n_u / n_rated >= 0.5]
cat("PIP props 'repeatedly failing' (>=2 Unacceptable and >=50% of rated comfort-station inspections since 2025-01-01):",
    nrow(fail), "\n")
npr <- pr[, .(n_cs = .N, n_closed = sum(long_term_closure == "Yes")), by = prop_id]
closed_props <- npr[n_closed > 0]
cat("PIP props with a long-term-closed station:", nrow(closed_props), "; all stations closed:",
    sum(closed_props$n_closed == closed_props$n_cs), "\n")

al <- fread(file.path(D, "pipAllSites_buk3-3qpr_20260920.csv"), showProgress = FALSE,
            select = c("prop_id", "prop_name", "site_name", "multipolygon.coordinates"))
need <- unique(c(closed_props$prop_id, fail$prop_id))
al <- al[prop_id %in% need & !is.na(multipolygon.coordinates) & nzchar(multipolygon.coordinates) & !duplicated(prop_id)]
geo <- lapply(al$multipolygon.coordinates, function(s) { x <- fromJSON(s, simplifyVector = FALSE)
  tryCatch(st_multipolygon(lapply(x, function(p) lapply(p, function(rg) do.call(rbind, lapply(rg, function(pt) c(pt[[1]], pt[[2]])))))),
           error = function(e) NULL) })
ok <- !vapply(geo, is.null, TRUE)
pp <- st_transform(st_make_valid(st_sf(al[ok, .(prop_id, prop_name, site_name)], geometry = st_sfc(geo[ok], crs = 4326))), 2263)
cat("problem props with polygon:", nrow(pp), "of", length(need), "\n")
# register rows (NYC Parks operator) within 30 m of each problem property polygon
rp <- rs[rs$operator == "NYC Parks", ]
hit <- st_is_within_distance(pp, rp, dist = M2FT(30))
mt <- data.table(prop_id = rep(pp$prop_id, lengths(hit)), facility_id = rp$facility_id[unlist(hit)])
mt <- merge(mt, r[, c("facility_id", "status")], by = "facility_id")
mt <- merge(mt, npr, by = "prop_id", all.x = TRUE)
mt[is.na(n_cs), `:=`(n_cs = 1L, n_closed = 0L)]     # failing prop without a pipRestrooms row: assume 1 station
# ambiguity rule: act only when #matched register rows <= #comfort stations at the property
mt[, n_match := .N, by = prop_id]
mt[, unambiguous := n_match <= n_cs]

cl_all <- closed_props[n_closed == n_cs]$prop_id                  # fully closed properties only
m_cl <- mt[prop_id %in% cl_all & unambiguous == TRUE]
removed_closed <- unique(m_cl[status == "Operational"]$facility_id)
reopen_reg     <- unique(m_cl[status != "Operational"]$facility_id)
m_fl <- mt[prop_id %in% fail$prop_id & unambiguous == TRUE & status == "Operational"]
removed_fail   <- setdiff(unique(m_fl$facility_id), removed_closed)
unmatched_cl <- setdiff(cl_all, mt$prop_id)
unmatched_cl <- intersect(unmatched_cl, pp$prop_id)
amb_cl <- setdiff(intersect(cl_all, mt$prop_id), m_cl$prop_id)
cat(sprintf("closed props: fully closed %d | matched unambiguously %d (listed Operational -> removed: %d rows; not operational -> reopen: %d rows) | ambiguous %d | no register row within 30 m: %d (added at polygon point)\n",
            length(cl_all), uniqueN(m_cl$prop_id), length(removed_closed), length(reopen_reg), length(amb_cl), length(unmatched_cl)))
cat(sprintf("failing props: %d | with unambiguous Operational register match: %d props -> %d rows removed\n",
            nrow(fail), uniqueN(m_fl$prop_id), length(removed_fail)))

sup <- rs[, c("facility_id", "facility_name", "operator", "status", "location_type", "w_open", "w_close", "w_ok",
              "placeholder", "hours_of_operation", "latitude", "longitude")]
sup$src <- "register"
# unmatched fully-closed props: represent by polygon point-on-surface, placeholder hours
if (length(unmatched_cl)) {
  up <- pp[pp$prop_id %in% unmatched_cl, ]
  ug <- st_point_on_surface(st_geometry(up)); ll <- st_coordinates(st_transform(ug, 4326))
  ex <- st_sf(facility_id = 100000 + seq_along(unmatched_cl), facility_name = paste0(up$site_name, " (PIP ", up$prop_id, ")"),
              operator = "NYC Parks", status = "PIP long-term closed (no register row)", location_type = "Park",
              w_open = 8, w_close = 16, w_ok = TRUE, placeholder = TRUE, hours_of_operation = PLACEHOLDER,
              latitude = ll[, 2], longitude = ll[, 1], src = "pip_polygon", geometry = ug)
  sup <- rbind(sup, ex)
}
sup$operational    <- sup$status == "Operational"
sup$removed_closed <- sup$facility_id %in% removed_closed
sup$removed_fail   <- sup$facility_id %in% removed_fail
sup$reopen_add     <- sup$facility_id %in% reopen_reg | sup$src == "pip_polygon"
# reopened rows with no usable Wednesday hours -> Parks placeholder hours (they are all NYC Parks)
fixh <- sup$reopen_add & !(sup$w_ok & !is.na(sup$w_open))
sup$w_open[fixh] <- 8; sup$w_close[fixh] <- 16; sup$w_ok[fixh] <- TRUE; sup$placeholder[fixh] <- TRUE
stopifnot(sum(sup$operational) == 975)

# ---- 7. Pilot sites (resolved by Restroom_Rebuild/R/P1_pilot_sites.R) ------------------------
pil <- read.csv(file.path(BASE, "Restroom_Rebuild/outputs/pilot_sites.csv"))
stopifnot(nrow(pil) == 17, !anyDuplicated(pil$site_id))
pil_sf <- st_as_sf(pil[, c("site_id", "published_name", "borough", "lat", "lon")], coords = c("lon", "lat"),
                   crs = 4326, remove = FALSE) |> st_transform(2263)

# ---- 8. Sparse within-500 m incidence -------------------------------------------------------
RADII <- c(500, 400, 750)          # 500 m is the service standard; 400/750 are the radius sensitivity
inc <- list()
for (rad in RADII) for (o in names(demand)) {
  p <- demand[[o]]$pts; key <- paste0(o, "_", rad)
  inc[[key]] <- list(
    cand   = st_is_within_distance(cand, p,   dist = M2FT(rad)),   # candidate -> demand idx
    supply = st_is_within_distance(p, sup,    dist = M2FT(rad)),   # demand -> supply idx
    pilot  = st_is_within_distance(pil_sf, p, dist = M2FT(rad)))   # pilot -> demand idx
  cat(key, ": demand pts", length(p), " candidate->demand links", sum(lengths(inc[[key]]$cand)), "\n")
}

# NTA of each candidate (raw) + snapped to nearest residential NTA (ntatype 0), rule as P1/10_modelling_table
nres <- nta[nta$ntatype == "0", ]
j <- st_intersects(cand, nta)
cand$nta_raw <- nta$nta2020[vapply(j, function(x) if (length(x)) x[1] else NA_integer_, 1L)]
cand$nta_raw[is.na(cand$nta_raw)] <- nta$nta2020[st_nearest_feature(cand[is.na(cand$nta_raw), ], nta)]
isres <- cand$nta_raw %in% nres$nta2020
cand$nta <- cand$nta_raw
cand$nta[!isres] <- nres$nta2020[st_nearest_feature(cand[!isres, ], nres)]
stopifnot(!anyNA(cand$nta), all(cand$nta %in% nres$nta2020))
ll <- st_coordinates(st_transform(cand, 4326)); cand$lon <- ll[, 1]; cand$lat <- ll[, 2]

saveRDS(list(demand = lapply(demand, function(d) list(w = d$w, unit = d$unit)),
             demand_pts = lapply(demand, `[[`, "pts"),
             cand = cand, sup = sup, pil = pil_sf, inc = inc, nta = nta,
             counts = list(removed_closed = length(removed_closed), reopen_reg = length(reopen_reg),
                           reopen_polygon = length(unmatched_cl), removed_fail = length(removed_fail),
                           fail_props = nrow(fail), closed_props_full = length(cl_all), ambiguous_closed = length(amb_cl))),
        file.path(PT, "cache/prep.rds"))
cat("prep done in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
