# 01_geography.R -----------------------------------------------------------
# Pulls the geography backbone for the Restroom Gap rebuild and builds the
# taxi-zone -> census-tract crosswalk. Re-runnable; everything is cached.
# --------------------------------------------------------------------------

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
source(file.path(PROJ, "R", "geo_helpers.R"))
RAW <- file.path(PROJ, "data_raw")
STAMP <- "20260920"

suppressPackageStartupMessages(library(dplyr))

f <- function(x) file.path(RAW, x)

# --- boundaries -----------------------------------------------------------
tracts <- socrata_geojson("63ge-mke6", f(sprintf("nycopendata_63ge-mke6_tracts2020_%s.geojson", STAMP)))
ntas   <- socrata_geojson("9nt8-h7nd", f(sprintf("nycopendata_9nt8-h7nd_nta2020_%s.geojson", STAMP)))
tzones <- socrata_geojson("8meu-9t5y", f(sprintf("nycopendata_8meu-9t5y_taxizones_%s.geojson", STAMP)))

cat("\n=== boundary files ===\n")
for (nm in c("tracts", "ntas", "tzones")) {
  g <- get(nm)
  cat(sprintf("%-7s rows=%4d  crs=%s  geom=%s\n", nm, nrow(g),
              st_crs(g)$epsg, paste(unique(as.character(st_geometry_type(g))), collapse = "/")))
  cat("        cols:", paste(setdiff(names(g), "geometry"), collapse = ", "), "\n")
}

# --- FIX: taxi zone file is 263 ROWS but only 260 LocationIDs -------------
# Zone 56 (Corona) is 2 rows and zone 103 (Governors/Ellis/Liberty Is.) is 3.
# TLC's lookup gives those pieces their own ids (57, 104, 105) but the shapefile
# does not. Any join on locationid must dissolve first or trips get duplicated.
cat("\n=== taxi zone multipart fix ===\n")
tzones$locationid <- as.integer(tzones$locationid)
cat("rows:", nrow(tzones), " distinct locationid:", length(unique(tzones$locationid)), "\n")
cat("ids appearing more than once:",
    paste(unique(tzones$locationid[duplicated(tzones$locationid)]), collapse = ", "), "\n")
cat("ids in 1:263 absent from the shapefile:",
    paste(setdiff(1:263, tzones$locationid), collapse = ", "), "\n")
tz <- tzones %>% group_by(locationid, zone, borough) %>%
  summarise(geometry = st_union(geometry), .groups = "drop") %>% st_make_valid()
cat("after dissolve:", nrow(tz), "zones\n")
tzones <- tz

# --- cardinality checks (CONVENTIONS join rules) --------------------------
cat("\n=== key cardinality ===\n")
cat("tract geoid unique:", !any(duplicated(tracts$geoid)), " n =", nrow(tracts), "\n")
cat("nta2020 unique:    ", !any(duplicated(ntas$nta2020)), " n =", nrow(ntas), "\n")
cat("locationid unique: ", !any(duplicated(tzones$locationid)), " n =", nrow(tzones), "\n")
cat("tracts per NTA: n NTAs referenced by tracts =", length(unique(tracts$nta2020)), "\n")
print(table(table(tracts$nta2020))[1:5])

# tracts nest inside NTAs by construction -> verify via the attribute join
nta_from_tract <- sort(unique(tracts$nta2020))
cat("NTAs in tract file not in NTA file:", sum(!nta_from_tract %in% ntas$nta2020), "\n")
cat("NTAs in NTA file with no tract    :", sum(!ntas$nta2020 %in% nta_from_tract), "\n")

# --- taxi zone -> tract crosswalk (area weighted) -------------------------
cat("\n=== building taxi zone -> tract crosswalk ===\n")
xw <- areal_crosswalk(tzones, tracts, "locationid", "geoid")
xw <- xw %>% filter(w_from > 0.0005)          # drop slivers < 0.05% of the zone
xw <- xw %>% group_by(locationid) %>% mutate(w_from = w_from / sum(w_from)) %>% ungroup()

zone_stats <- xw %>%
  group_by(locationid) %>%
  summarise(n_tracts = n(), max_w = max(w_from), .groups = "drop")

cat("taxi zones with >=1 tract overlap:", nrow(zone_stats), "of", nrow(tzones), "\n")
cat("zones mapping to exactly ONE tract:", sum(zone_stats$n_tracts == 1), "\n")
cat("median tracts per zone:", median(zone_stats$n_tracts),
    " mean:", round(mean(zone_stats$n_tracts), 1),
    " max:", max(zone_stats$n_tracts), "\n")
cat("zones where the single biggest tract holds >=90% of the zone:",
    sum(zone_stats$max_w >= 0.90), "\n")
cat("median share held by the biggest tract:", round(median(zone_stats$max_w), 3), "\n")
cat("zones with NO tract overlap:",
    paste(setdiff(tzones$locationid, zone_stats$locationid), collapse = ", "), "\n")

# same thing against NTAs, for the "do they nest?" claim
xw_nta <- areal_crosswalk(tzones, ntas, "locationid", "nta2020")
xw_nta <- xw_nta %>% filter(w_from > 0.0005) %>%
  group_by(locationid) %>% mutate(w_from = w_from / sum(w_from)) %>% ungroup()
zs_nta <- xw_nta %>% group_by(locationid) %>%
  summarise(n_nta = n(), max_w = max(w_from), .groups = "drop")
cat("\n[taxi zone -> NTA] zones mapping to exactly one NTA:",
    sum(zs_nta$n_nta == 1), "of", nrow(zs_nta),
    " | biggest NTA >=90%:", sum(zs_nta$max_w >= 0.90),
    " | median n_nta:", median(zs_nta$n_nta), "\n")

write.csv(xw[, c("locationid", "geoid", "w_from")],
          f(sprintf("crosswalk_taxizone_to_tract_%s.csv", STAMP)), row.names = FALSE)
write.csv(xw_nta[, c("locationid", "nta2020", "w_from")],
          f(sprintf("crosswalk_taxizone_to_nta_%s.csv", STAMP)), row.names = FALSE)

# --- tract -> NTA lookup (exact, from the tract attributes) ---------------
lut <- st_drop_geometry(tracts)[, c("geoid", "boroct2020", "borocode", "boroname",
                                    "ct2020", "nta2020", "ntaname", "cdta2020", "cdtaname")]
lut$area_sqmi <- as.numeric(st_area(st_transform(tracts, NYC_CRS_FEET))) / 27878400
write.csv(lut, f(sprintf("lookup_tract_to_nta_%s.csv", STAMP)), row.names = FALSE)
cat("\ntract lookup written, rows =", nrow(lut),
    " total land area sq mi =", round(sum(lut$area_sqmi), 1), "\n")

cat("\nDONE 01_geography\n")
