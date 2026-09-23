# P1_pilot_sites.R -------------------------------------------------------------
# QUESTION: the City's 17-unit modular restroom pilot (Mayor's Office, 16 Sep 2026)
# -- where are the units relative to OUR unmet-need ranking? How many land in the
# six high-confidence NTAs (A6), how many in the 29 NTAs with ratio >= 1.5, how
# many in neither?
#
# SOURCE OF THE LIST (verbatim, cached):
#   data_raw/nycgov_mayor_pilot_release_20260923.html
#   https://www.nyc.gov/mayors-office/news/2026/09/mayor-mamdani-brings-17-new-public-bathrooms-to-neighborhoods-ac
#   The release gives NAMES only (parks, plazas, intersections), no addresses.
#   NYCEDC's copy of the release (edc.nyc/press-release/mayor-mamdani-brings-17-
#   new-public-bathrooms-nyc) returns HTTP 403 to scripts; Time Out (17 Sep) repeats
#   the same list with no extra detail. The exact spot of each unit inside a park
#   or plaza is NOT published.
#
# GEOCODING (keyless, cached in data_raw/ so the script reproduces offline)
#   Each published name is resolved from the most authoritative NYC source:
#     park    -> NYC Parks property polygon (parksprops_sf_20260920.rds, enfh-gkve)
#     plaza   -> NYC DOT Pedestrian Plazas polygon (k5k6-6jex)
#     corner  -> intersection of the two named streets, NYC street Centerline
#                (inkn-q76z, only the named streets pulled)
#     venue   -> NYC Planning Labs GeoSearch v2 (Yankee Stadium)
#   Polygons are represented by st_point_on_surface; the share of the polygon's
#   area in each NTA is also reported, so a unit placed anywhere in the park is
#   covered. EVERY site is ALSO sent to GeoSearch by its published name, and the
#   raw responses are cached; the top hit's distance from our point is reported
#   as an independent cross-check (GeoSearch cannot do intersections, and fuzzy
#   name matches can land in the wrong borough -- see the flags).
#
# NTA RULE: identical to 10_modelling_table.R -- residential 2020 NTAs (ntatype 0);
#   a point in a park/cemetery/airport NTA is snapped to the nearest residential
#   NTA. The raw (unsnapped) NTA is kept alongside.
# RANKING: model_nta_scored_20260920.csv resid_ratio (rank 1 = highest of 197);
#   the 29 = ratio >= 1.5; the six = A6 posterior P(RR > 1.5) > 0.95, recomputed
#   here with A6's exact model so the posterior rank is also reported.
# DISTANCES: straight line, EPSG:2263 (ft) -> metres.
# -----------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(jsonlite); library(MASS)})
sf_use_s2(FALSE); select <- dplyr::select

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D <- file.path(PROJ, "data_raw"); OUT <- file.path(PROJ, "outputs")
FT <- 0.3048006096
PULL <- "20260923"
SIX <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
         "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")

# ---- 1. The published list, parsed from the cached release ------------------
rel_f <- file.path(D, "nycgov_mayor_pilot_release_20260923.html")
stopifnot(file.exists(rel_f))
txt <- paste(readLines(rel_f, warn = FALSE, encoding = "UTF-8"), collapse = " ")
txt <- gsub("\\\\r\\\\n|\\\\\"", " ", txt)                      # page embeds escaped HTML
lis <- regmatches(txt, gregexpr("<li><b>[A-Za-z ]+: </b>[^<]+</li>", txt))[[1]]
lis <- unique(lis)
stopifnot(length(lis) == 5)
pub <- do.call(rbind, lapply(lis, function(l) {
  boro <- sub("<li><b>([A-Za-z ]+): </b>.*", "\\1", l)
  body <- trimws(sub(".*</b>([^<]+)</li>", "\\1", l))
  # list separator is ", " and a final " and " -- but intersections also use "and".
  parts <- strsplit(body, ", ")[[1]]
  last  <- parts[length(parts)]
  data.frame(borough = boro, raw = c(parts[-length(parts)], last))
}))
# the final comma-element holds "X and Y" (two sites) where X or Y may itself be "A and B".
# Resolved by hand against the text; asserted below so a change in the release fails loudly.
published <- c(
  "Bronx|Yankee Stadium", "Bronx|Admiral Farragut Playground", "Bronx|Mapes Park",
  "Bronx|Monsignor Raul Del Valle Square",
  "Brooklyn|Columbus Park", "Brooklyn|Milestone Park", "Brooklyn|Fulton Street and Truxton Street",
  "Brooklyn|Avenue C Plaza",
  "Queens|Astoria Boulevard South and 31st Street", "Queens|Northern Boulevard and 31st Street",
  "Queens|Northern Boulevard and 54th Street", "Queens|34th Avenue and 64th Street",
  "Manhattan|Cooper Square", "Manhattan|Malcolm X Plaza", "Manhattan|Delancey Street and Suffolk Street",
  "Manhattan|Plaza Alianza Dominicana",
  "Staten Island|North Shore Esplanade")
stopifnot(length(published) == 17)
for (p in published) { b <- sub("\\|.*", "", p); n <- sub(".*\\|", "", p)
  stopifnot(grepl(n, paste(pub$raw[pub$borough == b], collapse = " | "), fixed = TRUE)) }
cat("Release parsed: 5 borough lines, 17 sites verified verbatim against the text\n")

sites <- data.frame(site_id = sprintf("P%02d", 1:17),
                    borough = sub("\\|.*", "", published), published_name = sub(".*\\|", "", published))
# resolution plan (documented choice per site)
plan <- list(
  P01 = list(method = "geosearch_venue", key = "YANKEE STADIUM"),
  P02 = list(method = "parks", key = "X148H"),
  P03 = list(method = "parks", key = "X289"),
  P04 = list(method = "parks", key = "X009"),
  P05 = list(method = "parks", key = "B113C"),   # Brooklyn Columbus Park (Borough Hall); Manhattan's is M015
  P06 = list(method = "parks", key = "B063"),
  P07 = list(method = "corner", key = c("FULTON ST", "TRUXTON ST"), boro = "3"),
  P08 = list(method = "plaza", key = "Avenue C Plaza"),
  P09 = list(method = "corner", key = c("ASTORIA BLVD S", "31 ST"), boro = "4"),
  P10 = list(method = "corner", key = c("NORTHERN BLVD", "31 ST"), boro = "4"),
  P11 = list(method = "corner", key = c("NORTHERN BLVD", "54 ST"), boro = "4"),
  P12 = list(method = "corner", key = c("34 AVE", "64 ST"), boro = "4"),
  P13 = list(method = "plaza", key = "Cooper Square Plaza"),
  P14 = list(method = "plaza", key = "Malcolm X Plaza"),
  P15 = list(method = "corner", key = c("DELANCEY ST", "SUFFOLK ST"), boro = "1"),
  P16 = list(method = "plaza", key = "Plaza Alianza Dominicana"),
  P17 = list(method = "parks", key = c("R066", "R083")))   # TWO Parks properties carry this name

# ---- 2. Cached pulls ---------------------------------------------------------
curl_get <- function(url, dest) {
  if (file.exists(dest)) return(invisible(dest))
  st <- system2("curl", c("-s", "-L", "--max-time", "60", "-o", shQuote(dest), "-w", "%{http_code}", shQuote(url)), stdout = TRUE)
  if (st != "200") { unlink(dest); stop("HTTP ", st, " for ", url) }
  Sys.sleep(1); invisible(dest)
}
enc <- function(x) utils::URLencode(x, reserved = TRUE)
f_plaza <- file.path(D, paste0("nycdot_k5k6-6jex_plazas_polygon_", PULL, ".geojson"))
curl_get("https://data.cityofnewyork.us/resource/k5k6-6jex.geojson?$limit=1000&$order=:id", f_plaza)
cor_streets <- unique(unlist(lapply(plan[sapply(plan, `[[`, "method") == "corner"], function(p) paste0(p$boro, "|", p$key))))
where <- paste0("(", paste(sprintf("(boroughcode='%s' AND full_street_name='%s')", sub("\\|.*", "", cor_streets),
                                   sub(".*\\|", "", cor_streets)), collapse = " OR "), ")")
f_cl <- file.path(D, paste0("nyc_inkn-q76z_centerline_pilotstreets_", PULL, ".geojson"))
curl_get(paste0("https://data.cityofnewyork.us/resource/inkn-q76z.geojson?$limit=5000&$order=:id&$where=", enc(where)), f_cl)
f_gs <- file.path(D, paste0("geosearch_pilot_sites_", PULL, ".json"))
if (!file.exists(f_gs)) {
  gs <- list()
  for (i in seq_len(nrow(sites))) {
    q <- paste0(sites$published_name[i], ", ", sites$borough[i])
    tmp <- tempfile(fileext = ".json")
    curl_get(paste0("https://geosearch.planninglabs.nyc/v2/search?size=5&text=", enc(q)), tmp)
    gs[[sites$site_id[i]]] <- list(query = q, response = fromJSON(tmp, simplifyVector = FALSE))
  }
  write_json(gs, f_gs, auto_unbox = TRUE, pretty = TRUE, digits = NA)
}
gs <- fromJSON(f_gs, simplifyVector = FALSE)

# ---- 3. Resolve each site ----------------------------------------------------
parks <- readRDS(file.path(D, "parksprops_sf_20260920.rds")) |> st_transform(2263) |> st_make_valid()
plz <- st_read(f_plaza, quiet = TRUE) |> st_transform(2263) |> st_make_valid()
cl  <- st_read(f_cl, quiet = TRUE) |> st_transform(2263)
cat("plaza polygons:", nrow(plz), " centerline segments pulled:", nrow(cl), "\n")

res <- vector("list", 17); geoms <- vector("list", 17)
for (i in 1:17) {
  id <- sites$site_id[i]; p <- plan[[id]]; note <- ""; amb <- FALSE; poly <- NULL
  if (p$method == "parks") {
    x <- parks[parks$gispropnum %in% p$key, ]
    stopifnot(nrow(x) == length(p$key), all(grepl(sub(" \\(.*", "", sites$published_name[i]), x$signname, ignore.case = TRUE)))
    poly <- st_union(st_geometry(x)); pt <- st_point_on_surface(poly)
    src <- paste0("NYC Parks property ", paste(x$gispropnum, collapse = "+"), " '", x$signname[1], "' (", paste(x$location, collapse = " / "), ")")
    if (length(p$key) > 1) {
      amb <- TRUE
      note <- sprintf("Two Parks properties are named 'North Shore Esplanade': %s. Both assessed; point = on-surface point of their union.",
                      paste(sprintf("%s (%s, %.2f ac)", x$gispropnum, x$location, as.numeric(x$acres)), collapse = "; "))
    }
    if (id == "P05") { amb <- TRUE; note <- "Name also matches Columbus Park, Manhattan (M015, Chinatown). The release lists it under Brooklyn, so B113C (Cadman Plaza / Borough Hall) is used." }
  } else if (p$method == "plaza") {
    x <- plz[plz$plazaname == p$key, ]; stopifnot(nrow(x) == 1)
    poly <- st_geometry(x); pt <- st_point_on_surface(poly)
    src <- sprintf("NYC DOT plaza polygon '%s' (%s, %s to %s)", x$plazaname, x$onstreet, x$fromstreet, x$tostreet)
    if (id == "P14") { amb <- TRUE; note <- "GeoSearch's top hits for 'Malcolm X Plaza' are Malcolm X PLACE in East Elmhurst, Queens (one of the six). The DOT plaza (Malcolm X Blvd, W 110-111 St, Manhattan) is used." }
    if (id == "P16") { amb <- TRUE; note <- "Not in DOT's point file under this name (listed there as 'Audubon Plaza', same street segment); the polygon file carries 'Plaza Alianza Dominicana'. GeoSearch returns no match." }
  } else if (p$method == "corner") {
    a <- cl[cl$full_street_name == p$key[1] & cl$boroughcode == p$boro, ]
    b <- cl[cl$full_street_name == p$key[2] & cl$boroughcode == p$boro, ]
    ip <- suppressWarnings(st_intersection(st_union(a), st_union(b)))
    ip <- suppressWarnings(st_cast(st_collection_extract(ip, "POINT"), "POINT"))
    if (length(ip) == 0) {                       # streets do not touch in the centerline: nearest approach
      nl <- st_nearest_points(st_union(a), st_union(b)); pt <- st_centroid(nl)
      gap <- as.numeric(st_length(nl)) * FT; amb <- TRUE
      note <- sprintf("The two centerlines do not intersect; midpoint of their closest approach used (gap %.0f m).", gap)
    } else {
      spread <- if (length(ip) > 1) max(as.numeric(st_distance(ip))) * FT else 0
      pt <- st_centroid(st_union(ip))
      if (spread > 60) { amb <- TRUE; note <- sprintf("%d crossing points up to %.0f m apart (divided roadway/service roads); their centroid is used.", length(ip), spread) }
      else if (length(ip) > 1) note <- sprintf("%d crossing nodes within %.0f m (divided roadway); centroid used.", length(ip), spread)
    }
    src <- sprintf("Intersection of %s and %s, NYC Centerline inkn-q76z (borough %s)", p$key[1], p$key[2], p$boro)
  } else if (p$method == "geosearch_venue") {
    f <- gs[[id]]$response$features
    lab <- sapply(f, function(z) z$properties$label)
    k <- which(startsWith(toupper(lab), p$key))[1]; stopifnot(!is.na(k))
    xy <- unlist(f[[k]]$geometry$coordinates)
    pt <- st_transform(st_sfc(st_point(xy), crs = 4326), 2263)
    src <- sprintf("NYC GeoSearch venue '%s'", lab[k])
    amb <- TRUE
    note <- "A stadium is a large site; the unit's exact spot is not published. Checked against the stadium, Macombs Dam Park and the Yankee Stadium garages (share of their area by NTA reported)."
    poly <- st_union(st_geometry(parks[parks$gispropnum %in% c("X030", "X237"), ]))
  }
  geoms[[i]] <- list(pt = st_sfc(pt, crs = 2263), poly = if (is.null(poly)) NULL else st_sfc(poly, crs = 2263))
  # GeoSearch cross-check: top hit by published name
  f <- gs[[id]]$response$features
  if (length(f)) {
    xy <- unlist(f[[1]]$geometry$coordinates)
    g1 <- st_transform(st_sfc(st_point(xy), crs = 4326), 2263)
    gs_lab <- f[[1]]$properties$label; gs_d <- round(as.numeric(st_distance(g1, geoms[[i]]$pt)) * FT)
    gs_conf <- f[[1]]$properties$confidence; gs_mt <- f[[1]]$properties$match_type
  } else { gs_lab <- "(no result)"; gs_d <- NA; gs_conf <- NA; gs_mt <- NA }
  res[[i]] <- data.frame(site_id = id, method = p$method, geocode_source = src, ambiguous = amb, resolution_note = note,
                         geosearch_top_hit = gs_lab, geosearch_match_type = ifelse(is.null(gs_mt), NA, gs_mt),
                         geosearch_top_hit_distance_m = gs_d)
}
res <- bind_rows(res); sites <- cbind(sites, res[, -1])
pts <- do.call(c, lapply(geoms, `[[`, "pt"))
ll <- st_coordinates(st_transform(pts, 4326)); sites$lon <- round(ll[, 1], 6); sites$lat <- round(ll[, 2], 6)

# ---- 4. NTA assignment (10_modelling_table rule) + ranking --------------------
nta_all <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
nta <- nta_all |> filter(ntatype == 0) |> select(nta2020, ntaname, boroname)
raw_i <- st_within(pts, nta_all); sites$raw_nta <- nta_all$ntaname[sapply(raw_i, function(k) if (length(k)) k[1] else NA)]
sites$raw_ntatype <- nta_all$ntatype[sapply(raw_i, function(k) if (length(k)) k[1] else NA)]
res_i <- sapply(st_within(pts, nta), function(k) if (length(k)) k[1] else NA)
sites$snapped_to_residential <- is.na(res_i)
res_i[is.na(res_i)] <- st_nearest_feature(pts[is.na(res_i)], nta)
sites$nta2020 <- nta$nta2020[res_i]; sites$ntaname <- nta$ntaname[res_i]; sites$nta_borough <- nta$boroname[res_i]
stopifnot(all(sites$nta_borough == sites$borough))   # a site landing in the wrong borough = a geocode error

sc <- read.csv(file.path(D, "model_nta_scored_20260920.csv"))
stopifnot(nrow(sc) == 197, !anyDuplicated(sc$nta2020))
sc$ratio_rank <- rank(-sc$resid_ratio, ties.method = "min")
hi <- sc$nta2020[sc$resid_ratio >= 1.5]; stopifnot(length(hi) == 29)
# A6 posterior, same model/data as R/A6_empirical_bayes.R
d6 <- read.csv(file.path(D, "model_with_commercial_20260920.csv")) |> filter(!is.na(inc10k), !is.na(pov), pop_total > 0)
m6 <- glm.nb(events_311 ~ l_sub + l_jobs + l_hotel + l_rest + l_dens + inc10k + pov + old + boro + offset(log(pop_total)), data = d6)
d6$p15 <- 1 - pgamma(1.5, shape = m6$theta + d6$events_311, rate = m6$theta + fitted(m6))
d6$post_rank <- rank(-d6$p15, ties.method = "min")
six_ids <- d6$nta2020[d6$p15 > 0.95]
stopifnot(length(six_ids) == 6, setequal(d6$ntaname[d6$nta2020 %in% six_ids], SIX))
sites <- sites |> left_join(sc |> select(nta2020, resid_ratio, ratio_rank, events_311), by = "nta2020") |>
  left_join(d6 |> select(nta2020, p15, post_rank), by = "nta2020")
sites$in_29 <- sites$nta2020 %in% hi; sites$in_six <- sites$nta2020 %in% six_ids

six_poly <- nta[nta$nta2020 %in% six_ids, ]; hi_poly <- nta[nta$nta2020 %in% hi, ]
dmin <- function(p, polys) { dd <- as.numeric(st_distance(p, polys)) * FT; c(d = min(dd), i = which.min(dd)) }
for (i in 1:17) {
  a <- dmin(pts[i], six_poly); b <- dmin(pts[i], hi_poly)
  sites$dist_to_six_m[i] <- round(a[["d"]]); sites$nearest_six[i] <- six_poly$ntaname[a[["i"]]]
  sites$dist_to_29_m[i] <- round(b[["d"]]); sites$nearest_29[i] <- hi_poly$ntaname[b[["i"]]]
  # inside a polygon: distance to its boundary (how close to the edge)
  own <- nta[nta$nta2020 == sites$nta2020[i], ]
  sites$dist_to_own_boundary_m[i] <- round(as.numeric(st_distance(pts[i], st_cast(st_geometry(own), "MULTILINESTRING"))) * FT)
  # NTA edges follow street centrelines: a corner site can sit ON the boundary, so the
  # side of the street the unit is placed on decides its NTA. List every residential
  # NTA within 30 m (about one roadway width) with its ratio and group.
  near30 <- which(as.numeric(st_distance(pts[i], nta)) * FT <= 30)
  lab <- function(k) { id <- nta$nta2020[k]; r <- sc$resid_ratio[sc$nta2020 == id]
    sprintf("%s (%.2f%s)", nta$ntaname[k], r, ifelse(id %in% six_ids, ", six", ifelse(id %in% hi, ", 29", ""))) }
  sites$ntas_within_30m[i] <- paste(sapply(near30, lab), collapse = "; ")
  sites$n_ntas_within_30m[i] <- length(near30)
  sites$any_six_within_30m[i] <- any(nta$nta2020[near30] %in% six_ids)
  sites$any_29_within_30m[i]  <- any(nta$nta2020[near30] %in% hi)
  # polygon sites: share of the site's area in each residential NTA (after snapping park NTAs)
  pg <- geoms[[i]]$poly
  if (!is.null(pg)) {
    ix <- suppressWarnings(st_intersection(nta_all[, c("ntaname", "ntatype")], pg))
    ix$a <- as.numeric(st_area(ix)); ix <- ix[ix$a > 0, ]
    sh <- tapply(ix$a, ix$ntaname, sum) / sum(ix$a)
    sites$polygon_nta_shares[i] <- paste(sprintf("%s %.0f%%", names(sh), 100 * sh)[order(-sh)], collapse = "; ")
    sites$polygon_touches_six[i] <- any(as.numeric(st_distance(pg, six_poly)) == 0)
    sites$polygon_touches_29[i]  <- any(as.numeric(st_distance(pg, hi_poly)) == 0)
    sites$polygon_acres[i] <- round(as.numeric(st_area(pg)) / 43560, 2)
  } else { sites$polygon_nta_shares[i] <- NA; sites$polygon_touches_six[i] <- NA; sites$polygon_touches_29[i] <- NA; sites$polygon_acres[i] <- NA }
}
# North Shore Esplanade: report each candidate separately (the two properties can differ)
nse <- parks[parks$gispropnum %in% c("R066", "R083"), ]
nse_pts <- st_point_on_surface(st_geometry(nse))
nse_tab <- data.frame(gispropnum = nse$gispropnum, location = nse$location,
  nta = nta$ntaname[sapply(st_within(nse_pts, nta), function(k) if (length(k)) k[1] else st_nearest_feature(nse_pts, nta)[1])])
nse_tab$ratio <- sc$resid_ratio[match(nse_tab$nta, sc$ntaname)]; nse_tab$in_29 <- nse_tab$nta %in% sc$ntaname[sc$nta2020 %in% hi]
cat("\nNorth Shore Esplanade candidates:\n"); print(nse_tab, row.names = FALSE)

sites$group <- ifelse(sites$in_six, "six", ifelse(sites$in_29, "29_not_six", "neither"))
out <- sites |> mutate(resid_ratio = round(resid_ratio, 2), p15 = round(p15, 3)) |>
  select(site_id, borough, published_name, method, geocode_source, lat, lon, raw_nta, raw_ntatype, snapped_to_residential,
         nta2020, ntaname, resid_ratio, ratio_rank, posterior_p_gt_1.5 = p15, posterior_rank = post_rank, events_311,
         in_29, in_six, group, dist_to_six_m, nearest_six, dist_to_29_m, nearest_29, dist_to_own_boundary_m, n_ntas_within_30m, ntas_within_30m, any_six_within_30m, any_29_within_30m,
         polygon_acres, polygon_nta_shares, polygon_touches_six, polygon_touches_29,
         ambiguous, resolution_note, geosearch_top_hit, geosearch_match_type, geosearch_top_hit_distance_m)
write.csv(out, file.path(OUT, "pilot_sites.csv"), row.names = FALSE)

cat("\n=== PILOT SITES ===\n")
print(out |> transmute(site_id, published_name = substr(published_name, 1, 34), ntaname = substr(ntaname, 1, 30),
                       ratio = resid_ratio, rank = ratio_rank, prank = posterior_rank, group, d_six = dist_to_six_m,
                       d29 = dist_to_29_m, edge = dist_to_own_boundary_m, amb = ambiguous, gs_d = geosearch_top_hit_distance_m), row.names = FALSE)
tab <- table(factor(out$group, levels = c("six", "29_not_six", "neither")))
cat("\nHEADLINE: in six =", tab[["six"]], "| in 29 (incl. six) =", sum(out$in_29), "| neither =", tab[["neither"]], "\n")
cat("boundary-straddling (>1 NTA within 30 m):", sum(out$n_ntas_within_30m > 1), " | a six NTA within 30 m:", sum(out$any_six_within_30m),
    " | a 29 NTA within 30 m:", sum(out$any_29_within_30m), "\n")
cat("sites within 500 m of a six NTA:", sum(out$dist_to_six_m <= 500), " within 1 km:", sum(out$dist_to_six_m <= 1000), "\n")
cat("polygon sites touching a six NTA:", sum(out$polygon_touches_six %in% TRUE), "; touching a 29 NTA:", sum(out$polygon_touches_29 %in% TRUE), "\n")

js <- list(script = "R/P1_pilot_sites.R", built = as.character(Sys.Date()),
  source = list(release = "https://www.nyc.gov/mayors-office/news/2026/09/mayor-mamdani-brings-17-new-public-bathrooms-to-neighborhoods-ac",
                release_date = "2026-09-16", cached = basename(rel_f),
                nycedc_copy = "https://edc.nyc/press-release/mayor-mamdani-brings-17-new-public-bathrooms-nyc (HTTP 403 to scripts; same list per Time Out 17 Sep)",
                precision = "names only; exact unit spot inside a park/plaza is not published"),
  method = list(geocode = "Parks property polygons (enfh-gkve), DOT plaza polygons (k5k6-6jex), Centerline street intersections (inkn-q76z), GeoSearch v2 venue for Yankee Stadium; every name also sent to GeoSearch as a cross-check (cached)",
                nta_rule = "residential 2020 NTAs; park/cemetery/airport NTA points snapped to nearest residential (10_modelling_table.R)",
                ranking = "model_nta_scored_20260920 resid_ratio; 29 = ratio >= 1.5; six = A6 posterior P(RR>1.5) > 0.95"),
  headline = list(n_sites = 17, in_six = tab[["six"]], in_29_incl_six = sum(out$in_29), in_29_not_six = tab[["29_not_six"]],
                  neither = tab[["neither"]],
                  boundary_straddling = sum(out$n_ntas_within_30m > 1), six_within_30m = sum(out$any_six_within_30m),
                  in_29_or_within_30m = sum(out$in_29 | out$any_29_within_30m), within_500m_of_six = sum(out$dist_to_six_m <= 500),
                  polygon_touching_six = sum(out$polygon_touches_six %in% TRUE),
                  sites_in_six = out$published_name[out$in_six], sites_in_29 = out$published_name[out$in_29],
                  ambiguous_sites = out$published_name[out$ambiguous]),
  north_shore_esplanade_candidates = nse_tab,
  sites = out)
write_json(js, file.path(OUT, "pilot_sites.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
cat("Wrote outputs/pilot_sites.{csv,json}\n")
