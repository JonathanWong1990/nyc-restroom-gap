# E1_peer_city_per_capita.R ---------------------------------------------------
# QUESTION: how many government-run public toilets per 100,000 residents does
# New York have, compared with peer cities, counted the SAME way everywhere?
#
# ONE COUNTING RULE (applied to every city, including NYC):
#   CORE = a toilet facility that (a) is operated by government or under a
#   government contract (city / state / transit authority / public park body /
#   municipal street-furniture contract), (b) is open to the general public with
#   no purchase or membership, (c) is a dedicated public toilet -- on the street,
#   in a park or plaza, or at a transit stop -- and (d) is listed as operating
#   (not closed / suspended / under construction) where the list carries status.
#   EXCLUDED from CORE, but counted in sensitivities:
#     - toilets inside general civic buildings (libraries, community / recreation
#       centres, civic offices, museums, cemeteries)            -> BROAD
#     - portable / mobile / container units                     -> BROAD
#     - urinal-only units (pissoirs, urinoirs)                  -> BROAD
#     - private businesses in access schemes (Berlin "Kooperationstoilette",
#       London Community Toilet Scheme)                         -> access_scheme
#   A coin fee does NOT exclude a toilet from CORE (Berlin, Zurich charge 0.50 EUR /
#   CHF 1 at some units); the free-only count is reported as a sensitivity.
#   Unit = one listed facility (a building / kiosk). `sites_30m` merges CORE
#   points closer than 30 m (e.g. a men's and a wheelchair cabin side by side).
#
# Every input is cached in data_raw/peer_cities/ (downloaded 2026-09-24); this
# script only reads the cache. Population = official figure for the SAME
# boundary as the list, nearest year (sources in the POP table below).
# Output: outputs/peer_city_per_capita.{csv,json}
# -----------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(dplyr); library(jsonlite); library(readxl)})

PROJ <- Sys.getenv("RESTROOM_PROJ",
  unset = "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild")
PC  <- file.path(PROJ, "data_raw", "peer_cities")
OUT <- file.path(PROJ, "outputs")
ACCESSED <- "2026-09-24"

# greedy 30 m de-duplication of points (haversine) ---------------------------
sites_within <- function(lat, lon, m = 30) {
  ok <- is.finite(lat) & is.finite(lon); lat <- lat[ok]; lon <- lon[ok]
  if (!length(lat)) return(NA_integer_)
  keep_lat <- c(); keep_lon <- c()
  for (i in seq_along(lat)) {
    if (length(keep_lat)) {
      d <- 6371000 * 2 * asin(sqrt(sin((keep_lat - lat[i]) * pi / 360)^2 +
             cos(lat[i] * pi / 180) * cos(keep_lat * pi / 180) * sin((keep_lon - lon[i]) * pi / 360)^2))
      if (any(d < m)) next
    }
    keep_lat <- c(keep_lat, lat[i]); keep_lon <- c(keep_lon, lon[i])
  }
  length(keep_lat)
}
latlon_from_pair <- function(x) {      # "lat, lon" string -> 2 numeric vectors
  p <- strsplit(gsub("\\s", "", x), ","); list(lat = as.numeric(sapply(p, `[`, 1)), lon = as.numeric(sapply(p, `[`, 2)))
}
rows <- list()
add <- function(...) rows[[length(rows) + 1]] <<- tibble::tibble(...)

# ---- NEW YORK CITY (register i7jb-7jku, rows updated 2025-06-27) -------------
ny <- read.csv(file.path(PROJ, "data_raw", "nycrestrooms_i7jb-7jku_20260920.csv"))
ny_op    <- ny$status == "Operational"
ny_core  <- ny_op & ny$location_type %in% c("Park", "Public Plaza", "Transit")
ny_broad <- ny_op & ny$location_type %in% c("Park", "Public Plaza", "Transit", "Library")
stopifnot(sum(ny_op) == 975, sum(ny_core) == 763)
add(city = "New York City", grade = "A",
    listed = sum(ny$location_type %in% c("Park", "Public Plaza", "Transit")),
    core = sum(ny_core), broad = sum(ny_broad), free_only = sum(ny_core),
    access_scheme = NA_integer_, register_all_operational = sum(ny_op),
    sites_30m = sites_within(ny$latitude[ny_core], ny$longitude[ny_core]),
    core_def = "status Operational AND location_type Park / Public Plaza / Transit (NYC Parks, concessionaires, Hudson River Park, BBP, BPCA, conservancies, DOT/JCDecaux, LIRR/MNR/NYCT)",
    broad_adds = "+199 library restrooms (NYPL/BPL/QPL)",
    excluded = "13 POPS (privately owned, operated by landlords); 91 not operational / closed / construction",
    data_date = "2025-06-27 (rowsUpdatedAt; pulled 2026-09-20)",
    source_url = "https://data.cityofnewyork.us/d/i7jb-7jku",
    file = "data_raw/nycrestrooms_i7jb-7jku_20260920.csv")

# ---- PARIS (opendata.paris.fr 'sanisettesparis') ------------------------------
pa <- read.csv2(file.path(PC, "paris_sanisettesparis_20260924.csv"), fileEncoding = "UTF-8-BOM")
pa_ll <- latlon_from_pair(pa$geo_point_2d)
pa_toilet <- pa$type %in% c("Sanisette", "WC", "Lavatory")
pa_core   <- pa_toilet & pa$statut == "En service"
pa_broad  <- pa$statut == "En service"                         # + urinals
add(city = "Paris", grade = "A", listed = sum(pa_toilet), core = sum(pa_core),
    broad = sum(pa_broad), free_only = sum(pa_core), access_scheme = NA_integer_,
    register_all_operational = sum(pa_broad),
    sites_30m = sites_within(pa_ll$lat[pa_core], pa_ll$lon[pa_core]),
    core_def = "type Sanisette / WC (park & garden toilets) / Lavatory AND statut 'En service'",
    broad_adds = "+ urinals (Urinoir) in service",
    excluded = "toilets inside mairies, libraries, museums (not in the list); units 'Hors service'",
    data_date = "live export 2026-09-24",
    source_url = "https://opendata.paris.fr/explore/dataset/sanisettesparis/",
    file = "data_raw/peer_cities/paris_sanisettesparis_20260924.csv")

# ---- ZURICH (Stadt Zürich OGD 'Züri WC', WFS layers) --------------------------
zread <- function(f) {
  g <- fromJSON(file.path(PC, f), simplifyVector = FALSE)$features
  tibble::tibble(name = sapply(g, function(x) x$properties$name),
                 typ  = sapply(g, function(x) x$properties$typ %||% ""),
                 fee  = sapply(g, function(x) x$properties$gebuehren %||% ""),
                 lon  = sapply(g, function(x) x$geometry$coordinates[[1]]),
                 lat  = sapply(g, function(x) x$geometry$coordinates[[2]]), layer = f)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
zf <- bind_rows(zread("zurich_zueriwc_20260924.geojson"), zread("zurich_poi_zueriwc_rs_view_20260924.geojson"))
zm <- bind_rows(zread("zurich_poi_zueriwc_mobil_view_20260924.geojson"), zread("zurich_poi_zueriwc_mobil_rs_view_20260924.geojson"))
z_core <- zf$typ != "Pissoir"
z_free <- grepl("gratis|frei|kostenlos", zf$fee, ignore.case = TRUE)
add(city = "Zurich", grade = "A", listed = sum(z_core), core = sum(z_core),
    broad = nrow(zf) + nrow(zm), free_only = sum(z_core & z_free), access_scheme = NA_integer_,
    register_all_operational = nrow(zf) + nrow(zm),
    sites_30m = sites_within(zf$lat[z_core], zf$lon[z_core]),
    core_def = "Züri WC fixed facilities (wheelchair + non-wheelchair layers), excluding pissoirs; no status field (all listed assumed operating)",
    broad_adds = "+4 pissoirs, +23 mobile (seasonal) WCs",
    excluded = "none further; list is the city's own (GUD, Umwelt- und Gesundheitsschutz)",
    data_date = "records edited 2024-12 to 2026-08; pulled 2026-09-24",
    source_url = "https://data.stadt-zuerich.ch/dataset/geo_zueri_wc",
    file = "data_raw/peer_cities/zurich_*.geojson")

# ---- HONG KONG (FEHD facility XML, generated 2026-09-21) ----------------------
hx <- xml2_available <- requireNamespace("xml2", quietly = TRUE)
stopifnot(hx)
hk <- xml2::read_xml(file.path(PC, "hk_fehd_map_e_20260924.xml"))
m  <- xml2::xml_find_all(hk, ".//fehd_service_locations/map")
hkd <- tibble::tibble(type = xml2::xml_text(xml2::xml_find_first(m, "map_type")),
                      rem  = xml2::xml_text(xml2::xml_find_first(m, "remarks_e")),
                      co   = xml2::xml_text(xml2::xml_find_first(m, "map_coordinate")))
hk_ll <- latlon_from_pair(hkd$co)
hk_susp <- grepl("suspen", hkd$rem, ignore.case = TRUE)   # "Suspension Period: ...", "Suspended on ...", "Permanently suspended"
hk_core <- hkd$type == "toilet" & !hk_susp
HK_LCSD_APPROX <- 630   # LegCo Research Office, ISE04/19-20 (Nov 2019): "some 630 facilities and venues with public toilets under LCSD"
add(city = "Hong Kong", grade = "B", listed = sum(hkd$type == "toilet"), core = sum(hk_core),
    broad = sum(hk_core) + sum(hkd$type == "ap" & !hk_susp) + sum(hkd$type == "portable_toilet") + HK_LCSD_APPROX,
    free_only = sum(hk_core), access_scheme = NA_integer_,
    register_all_operational = sum(hkd$type %in% c("toilet", "ap", "portable_toilet") & !hk_susp),
    sites_30m = sites_within(hk_ll$lat[hk_core], hk_ll$lon[hk_core]),
    core_def = "FEHD map_type 'toilet', excluding units whose remark says suspended (temporary or permanent)",
    broad_adds = "+31 aqua privies, +122 long-term portable toilets (FEHD), +~630 LCSD park/sports-venue toilets (LegCo 2019, approximate, no list)",
    excluded = "LCSD park and sports-venue toilets are NOT in the FEHD list -- the list is PARTIAL for this rule (NYC's core is mostly park toilets)",
    data_date = "XML generation_date 2026-09-21",
    source_url = "https://data.gov.hk/en-data/dataset/hk-fehd-fehdlocatn-fehd-facility-and-service-locations",
    file = "data_raw/peer_cities/hk_fehd_map_e_20260924.xml")

# ---- SAN FRANCISCO (DataSF wfq4-upmv) ------------------------------------------
sf <- read.csv(file.path(PC, "sf_wfq4-upmv_20260924.csv"))
sf_r <- sf[sf$resource_type == "restroom", ]
sf_pub <- sf_r$access == "publicly_accessible"
add(city = "San Francisco", grade = "B", listed = nrow(sf_r), core = nrow(sf_r),
    broad = nrow(sf_r), free_only = nrow(sf_r), access_scheme = NA_integer_,
    register_all_operational = nrow(sf_r),
    sites_30m = sites_within(sf_r$latitude, sf_r$longitude),
    core_def = "resource_type 'restroom' from Rec & Park (174), Public Works Pit Stops (16), Port (14), PUC (1); no status field",
    broad_adds = sprintf("none available; %d of %d are 'publicly_accessible' (rest 'limited_access')", sum(sf_pub), nrow(sf_r)),
    excluded = "street JCDecaux toilets not staffed as Pit Stops appear to be missing; library restrooms not listed (library source has fountains only)",
    data_date = "data_as_of 2024-06 to 2026-09-01; loaded 2026-09-01",
    source_url = "https://data.sfgov.org/d/wfq4-upmv",
    file = "data_raw/peer_cities/sf_wfq4-upmv_20260924.csv")

# ---- TORONTO (City of Toronto open data: park washrooms, APTs, CREM) ----------
tp <- read.csv(file.path(PC, "toronto_park_washrooms_20260924.csv"), check.names = FALSE)
ta <- read.csv(file.path(PC, "toronto_apt_washrooms_20260924.csv"))
tc <- read.csv(file.path(PC, "toronto_crem_washrooms_20260924.csv"), check.names = FALSE)
geo_ll <- function(g) {                      # '{"coordinates": [[lon, lat]], ...}'
  n <- regmatches(g, regexpr("-?[0-9.]+,\\s*-?[0-9.]+", g)); p <- strsplit(n, ",\\s*")
  list(lon = as.numeric(sapply(p, `[`, 1)), lat = as.numeric(sapply(p, `[`, 2)))
}
tp_ll <- geo_ll(tp$geometry); ta_ll <- geo_ll(ta$geometry)
tp_open <- tp$Status %in% c(1, 2)            # 1 open, 2 partially open, 0 closed (repairs / season / construction)
ta_ok <- ta$STATUS == "Existing"
n_crem_bldg <- length(unique(tc$`Building Description`))
add(city = "Toronto", grade = "A", listed = nrow(tp) + sum(ta_ok),
    core = sum(tp_open) + sum(ta_ok), broad = sum(tp_open) + sum(ta_ok) + n_crem_bldg,
    free_only = sum(tp_open) + sum(ta_ok), access_scheme = NA_integer_,
    register_all_operational = sum(tp_open) + sum(ta_ok) + n_crem_bldg,
    sites_30m = sites_within(c(tp_ll$lat[tp_open], ta_ll$lat[ta_ok]), c(tp_ll$lon[tp_open], ta_ll$lon[ta_ok])),
    core_def = "Parks washroom facilities with Status 1 (open) or 2 (partially open) + automated public washrooms 'Existing'",
    broad_adds = sprintf("+%d civic buildings with public washrooms (CREM list: 119 washroom rooms)", n_crem_bldg),
    excluded = "41 park washrooms Status 0 (closed for repairs / season / construction) on 2026-09-22; community-centre washrooms not in these lists",
    data_date = "park list refreshed 2026-09-22; APT 2026-02-20; CREM 2026-06-22",
    source_url = "https://open.toronto.ca/dataset/washroom-facilities/ ; https://open.toronto.ca/dataset/street-furniture-public-washroom/ ; https://open.toronto.ca/dataset/corporate-real-estate-management-portfolio-washrooms/",
    file = "data_raw/peer_cities/toronto_*.csv")

# ---- VANCOUVER (City of Vancouver open data 'public-washrooms') ---------------
va <- read.csv2(file.path(PC, "vancouver_public-washrooms_20260924.csv"), fileEncoding = "UTF-8-BOM", check.names = FALSE)
va_ll <- latlon_from_pair(va$geo_point_2d)
va_core_types <- c("LargeAPT", "SmallAPT", "ComfortStation", "Park - Field House",
                   "Park - Public Washroom", "Park - Portland Loo")
va_core <- va$type %in% va_core_types
add(city = "Vancouver", grade = "A", listed = sum(va_core), core = sum(va_core), broad = nrow(va),
    free_only = sum(va_core), access_scheme = NA_integer_, register_all_operational = nrow(va),
    sites_30m = sites_within(va_ll$lat[va_core], va_ll$lon[va_core]),
    core_def = "street APTs (large/small), comfort stations, park field houses, park washrooms, Portland Loos; no status field",
    broad_adds = "+28 community centres, +1 aquatic centre, +3 other (VanDusen garden, aquarium plaza), +1 portable",
    excluded = "none further",
    data_date = "dataset modified 2026-09-19",
    source_url = "https://opendata.vancouver.ca/explore/dataset/public-washrooms/",
    file = "data_raw/peer_cities/vancouver_public-washrooms_20260924.csv")

# ---- BERLIN (SenMVKU 'Standorte der öffentlichen Toiletten') ------------------
be <- read_excel(file.path(PC, "berlin_toiletten_standorte_20260924.xlsx"), sheet = "Berlinweit")
be_lat <- as.numeric(gsub(",", ".", be$Breitengrad)); be_lon <- as.numeric(gsub(",", ".", be$Längengrad))
be_bldg <- c("Bibliothek", "Bürgeramt", "öffentliches Gebäude", "Museum", "Friedhof")
be_pub  <- be$Vertrag %in% c(1, 2, 3)                # 1 Wall contract, 2 container, 3 other public; 4 = privately operated
be_core <- be_pub & be$Symbol == "WC" & !(be$Modelltyp %in% c(be_bldg, "Sanitärcontainer"))
be_broad <- be_pub & be$Symbol %in% c("WC", "Pissoir")
add(city = "Berlin", grade = "A", listed = sum(be_core), core = sum(be_core), broad = sum(be_broad),
    free_only = sum(be_core & be$Nutzungsentgelt %in% "0"),
    access_scheme = sum(be$Modelltyp %in% "Kooperationstoilette"),
    register_all_operational = nrow(be),
    sites_30m = sites_within(be_lat[be_core], be_lon[be_core]),
    core_def = "Vertrag 1/2/3 (Wall contract, container, other public) AND Symbol 'WC' (not event-only), excluding toilets in civic buildings / cemeteries and sanitary containers",
    broad_adds = "+ library / Bürgeramt / public-building / museum / cemetery toilets, + containers, + pissoirs",
    excluded = "31 privately operated station/other toilets (Vertrag 4), 13 'Kooperationstoilette' cafés (access scheme), 11 event-only WCs",
    data_date = "list updated 2026-08-25",
    source_url = "https://daten.berlin.de/datensaetze/toiletten",
    file = "data_raw/peer_cities/berlin_toiletten_standorte_20260924.xlsx")

# ---- MELBOURNE (City of Melbourne open data) -- GRADE C, reported not ranked -------
me <- read.csv(file.path(PC, "melbourne_public-toilets_20260924.csv"), fileEncoding = "UTF-8-BOM")
add(city = "Melbourne (City of Melbourne LGA)", grade = "C", listed = nrow(me), core = nrow(me), broad = nrow(me),
    free_only = nrow(me), access_scheme = NA_integer_, register_all_operational = nrow(me),
    sites_30m = sites_within(me$lat, me$lon),
    core_def = "all 74 council-operated toilets in the council list",
    broad_adds = "none", excluded = "list last modified 2021-09-30 (stale); LGA is the CBD with a small resident base",
    data_date = "2021-09-30 (dataset modified)",
    source_url = "https://data.melbourne.vic.gov.au/explore/dataset/public-toilets/",
    file = "data_raw/peer_cities/melbourne_public-toilets_20260924.csv")

tab <- bind_rows(rows)

# ---- POPULATION: same boundary as each list --------------------------------
acs <- read.csv(file.path(PC, "us_acs5y2024_b01003_counties_extract.psv"), sep = "|")
ny_pop <- sum(acs$B01003_E001[acs$GEO_ID %in% paste0("0500000US36", c("005","047","061","081","085"))])
stopifnot(ny_pop == 8483844)
zp <- read.csv(file.path(PC, "zurich_pop_BEV324OD3243_20260924.csv"), fileEncoding = "UTF-8-BOM")
ca <- read.csv(file.path(PC, "canada_statcan_17100155_toronto_vancouver_extract.csv"), check.names = FALSE, fileEncoding = "UTF-8-BOM")
capop <- function(g) ca$VALUE[ca$REF_DATE == 2025 & grepl(g, ca$GEO)]
POP <- tibble::tribble(
  ~city, ~population, ~pop_year, ~pop_boundary, ~pop_source,
  "New York City", ny_pop, "ACS 2020-24 5-yr", "five boroughs (5 counties)", "US Census ACS 5-yr 2024, table B01003 (project base); cached extract us_acs5y2024_b01003_counties_extract.psv",
  "Paris", 2103778, "2023 (in force 1 Jan 2026)", "Commune de Paris (75056)", "INSEE, Populations de référence 2023, population municipale: https://www.insee.fr/fr/statistiques/8643952?geo=COM-75056",
  "Zurich", zp$AnzBestWir[zp$StichtagDatJahr == 2025], "31 Dec 2025", "Stadt Zürich", "Statistik Stadt Zürich, Bevölkerungsbestand (BEV324OD3243): https://data.stadt-zuerich.ch/dataset/bev_bestand_jahr_od3243",
  "Hong Kong", 7527500, "mid-2025 (provisional)", "Hong Kong SAR", "C&SD press release 14 Aug 2025: https://www.info.gov.hk/gia/general/202508/14/P2025081400404.htm",
  "San Francisco", acs$B01003_E001[acs$GEO_ID == "0500000US06075"], "ACS 2020-24 5-yr", "City and County of San Francisco", "US Census ACS 5-yr 2024, table B01003 (same vintage as NYC base)",
  "Toronto", capop("Toronto"), "1 Jul 2025", "City of Toronto (CSD 3520005)", "Statistics Canada Table 17-10-0155-01: https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1710015501",
  "Vancouver", capop("Vancouver"), "1 Jul 2025", "City of Vancouver (CSD 5915022)", "Statistics Canada Table 17-10-0155-01",
  "Berlin", 3700577, "31 Dec 2025", "Land Berlin", "Amt für Statistik Berlin-Brandenburg, press release 22 Jun 2026: https://www.statistik-berlin-brandenburg.de/presse/2026/73-bevoelkerungsfortschreibung-2025-berlin/",
  "Melbourne (City of Melbourne LGA)", 189381, "30 Jun 2024", "City of Melbourne LGA", "ABS ERP via profile.id.com.au/melbourne/population-estimate (secondary; list is 2021 so years mismatch)")

per100k <- function(n, p) round(n / p * 1e5, 1)
tab <- tab |> left_join(POP, by = "city") |>
  mutate(per100k_core = per100k(core, population),
         per100k_listed = per100k(listed, population),
         per100k_broad = per100k(broad, population),
         per100k_free_only = per100k(free_only, population),
         per100k_sites30m = per100k(sites_30m, population),
         per100k_access_scheme_added = ifelse(is.na(access_scheme), NA, per100k(core + access_scheme, population)),
         accessed = ACCESSED) |>
  arrange(grade == "C", desc(per100k_core))

# Hong Kong: core + LCSD approximation (the like-for-like number for NYC's park-heavy core)
hk_row <- tab$city == "Hong Kong"
tab$per100k_hk_with_lcsd <- ifelse(hk_row, per100k(tab$core + HK_LCSD_APPROX, tab$population), NA)

# NYC rank among graded A/B cities, on core and on each sensitivity ---------
ab <- tab |> filter(grade %in% c("A", "B"))
rank_of <- function(col) which(ab$city[order(-ab[[col]])] == "New York City")
ranks <- sapply(c("per100k_core", "per100k_listed", "per100k_broad", "per100k_free_only", "per100k_sites30m"), rank_of)

write.csv(tab, file.path(OUT, "peer_city_per_capita.csv"), row.names = FALSE)
write_json(list(about = "Public toilets per 100,000 residents, one counting rule for every city. Generated by R/E1_peer_city_per_capita.R from data_raw/peer_cities/ (accessed 2026-09-24).",
                rule = "CORE = government-operated or contracted, open to all without purchase, dedicated public toilet (street / park / plaza / transit), listed as operating. Civic-building toilets, portables and urinals are in BROAD; access-scheme businesses are counted separately.",
                nyc_rank_among_AB = as.list(ranks), n_AB = nrow(ab),
                hk_lcsd_approx = HK_LCSD_APPROX,
                table = tab),
           file.path(OUT, "peer_city_per_capita.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)

print(as.data.frame(tab[, c("city", "grade", "listed", "core", "broad", "free_only", "sites_30m", "population",
                            "per100k_core", "per100k_listed", "per100k_broad", "per100k_free_only", "per100k_sites30m")]))
cat("\nNYC rank among", nrow(ab), "A/B cities:\n"); print(ranks)
cat("HK core + ~630 LCSD:", tab$per100k_hk_with_lcsd[hk_row], "per 100k\n")
