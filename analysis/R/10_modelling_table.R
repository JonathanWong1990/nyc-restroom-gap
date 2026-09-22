# 10_modelling_table.R — build the NTA-level modelling table.
# Unit: residential 2020 NTAs (n=197). Distances in EPSG:2263 (US survey feet).
suppressMessages({library(sf); library(dplyr)})
options(scipen = 999)
D <- "data_raw"; ok <- function(...) cat("  [ok]", ..., "\n")

## Only ntatype==0 are residential neighbourhoods (197 of 262); the rest are parks,
## cemeteries and airports. A point landing in one of those used to be dropped, which
## silently moved supply out of the neighbourhood it actually serves -- e.g. a restroom
## in Kissena Park never counted for East Flushing, 106m away. Assign to the nearest
## residential NTA instead of discarding.
nta_all <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263)
nta <- nta_all |> filter(ntatype == 0) |> select(nta2020, geometry)
base <- read.csv(file.path(D,"nta_analysis_base_20260920.csv"))
cat("NTA polygons:", nrow(nta), " base rows:", nrow(base),
    " residential:", sum(base$is_residential), "\n")

to_nta <- function(df, lon="longitude", lat="latitude"){
  df <- df[!is.na(df[[lon]]) & !is.na(df[[lat]]), ]
  p <- st_as_sf(df, coords=c(lon,lat), crs=4326) |> st_transform(2263)
  j <- st_join(p, nta, join=st_within)
  miss <- is.na(j$nta2020)
  if (any(miss)) {
    j$nta2020[miss] <- nta$nta2020[st_nearest_feature(j[miss, ], nta)]
    cat("  outside the residential set, snapped to nearest:", sum(miss), "\n")
  }
  cat("  assigned:", sum(!is.na(j$nta2020)), "/", nrow(j),
      sprintf(" (%.1f%%)\n", 100*mean(!is.na(j$nta2020))))
  j
}

## ---- SUPPLY: operational, year-round restrooms -----------------------------
cat("\n[restrooms]\n")
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"))
print(table(rr$status, useNA="ifany")); print(table(rr$open, useNA="ifany"))
rr_op <- rr |> filter(status=="Operational", open=="Year Round")
cat("operational + year-round:", nrow(rr_op), "\n")
rr_sf <- to_nta(rr_op)
supply <- rr_sf |> st_drop_geometry() |> filter(!is.na(nta2020)) |>
  count(nta2020, name="restrooms")

## ---- DEMAND: subway (complex-level; ak4z is already per complex) -----------
cat("\n[subway]\n")
mta <- read.csv(file.path(D,"mta_ak4z-sape_monthly_20260920.csv"))
cat("months:", min(mta$month), "->", max(mta$month), "\n")
last12 <- sort(unique(mta$month), decreasing=TRUE)[1:12]
stn <- mta |> filter(month %in% last12) |>
  group_by(station_complex_id) |>
  summarise(ridership = sum(ridership, na.rm=TRUE),
            latitude = first(latitude), longitude = first(longitude), .groups="drop")
cat("complexes:", nrow(stn), " cardinality check (rows per complex):\n")
print(mta |> filter(month %in% last12) |> count(station_complex_id) |> count(n))
stn_sf <- to_nta(stn)
subway <- stn_sf |> st_drop_geometry() |> filter(!is.na(nta2020)) |>
  group_by(nta2020) |> summarise(subway_riders = sum(ridership), n_stations = n(), .groups="drop")

## ---- DEMAND: workplace jobs (LODES block -> tract -> NTA) ------------------
cat("\n[jobs]\n")
lodes <- read.csv(file.path(D,"census_lodes8_nywac2023_20260920.csv"), colClasses=c(w_geocode="character"))
lodes$geoid <- substr(lodes$w_geocode, 1, 11)
xw <- read.csv(file.path(D,"lookup_tract_to_nta_20260920.csv"), colClasses=c(geoid="character"))
cat("tract->NTA cardinality:\n"); print(xw |> count(geoid) |> count(n))
jobs <- lodes |> inner_join(xw |> select(geoid, nta2020), by="geoid") |>
  group_by(nta2020) |> summarise(jobs = sum(C000, na.rm=TRUE), .groups="drop")
cat("jobs matched:", sum(lodes$geoid %in% xw$geoid), "/", nrow(lodes),
    " total jobs:", format(sum(jobs$jobs), big.mark=","), "\n")

## ---- DEMAND: hotels (one tax year, distinct buildings) ---------------------
cat("\n[hotels]\n")
ht <- read.csv(file.path(D,"nyc_tjus-cn27_hotels_20260920.csv"))
print(table(ht$taxyear))
yr <- max(ht$taxyear, na.rm=TRUE)
ht1 <- ht |> filter(taxyear==yr) |> distinct(bbl, .keep_all=TRUE)
cat("year", yr, "distinct bbl:", nrow(ht1), "\n")
hotels <- to_nta(ht1) |> st_drop_geometry() |> filter(!is.na(nta2020)) |>
  count(nta2020, name="hotels")

## ---- assemble --------------------------------------------------------------
tab <- base |> filter(is_residential==TRUE | is_residential=="True" | is_residential==1) |>
  left_join(supply, by="nta2020") |> left_join(subway, by="nta2020") |>
  left_join(jobs,   by="nta2020") |> left_join(hotels, by="nta2020") |>
  mutate(across(c(restrooms, subway_riders, n_stations, jobs, hotels), ~tidyr::replace_na(.x, 0)))

area <- nta |> mutate(area_sqmi = as.numeric(st_area(geometry))/27878400) |>
  st_drop_geometry()
tab <- tab |> left_join(area, by="nta2020") |>
  mutate(pop_density = pop_total/area_sqmi,
         jobs_density = jobs/area_sqmi)

cat("\nFINAL TABLE:", nrow(tab), "rows x", ncol(tab), "cols\n")
cat("zero restrooms:", sum(tab$restrooms==0), " zero subway:", sum(tab$subway_riders==0), "\n")
write.csv(tab, file.path(D,"model_nta_table_20260920.csv"), row.names=FALSE)
saveRDS(list(nta=nta, rr=rr_sf, stn=stn_sf), file.path(D,"model_spatial_20260920.rds"))
ok("wrote model_nta_table_20260920.csv")
