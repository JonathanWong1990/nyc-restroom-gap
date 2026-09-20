# 31_coverage_validation.R — population-weighted 5-min-walk coverage, to compare
# against NYC Council's published 49.42% of residents.
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv")) |>
  filter(status=="Operational", open=="Year Round", !is.na(latitude), !is.na(longitude))
rr_sf <- st_as_sf(rr, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)
cov <- st_union(st_buffer(rr_sf, 400/0.3048))

tr <- st_read(file.path(D,"nycopendata_63ge-mke6_tracts2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263)
gcol <- grep("geoid|GEOID", names(tr), value=TRUE)[1]
tr$geoid <- as.character(tr[[gcol]])
acs <- read.csv(file.path(D,"census_acs5_2024_tract_demographics_20260920.csv"),
                colClasses=c(geoid="character"))
pcol <- grep("pop_total|population|^pop$", names(acs), value=TRUE)[1]
cat("tracts:", nrow(tr), " acs rows:", nrow(acs), " pop col:", pcol, "\n")

tr <- tr |> inner_join(acs |> select(geoid, pop=all_of(pcol)), by="geoid") |>
  filter(!is.na(pop), pop > 0)
cat("tracts with population:", nrow(tr), " total pop:", format(sum(tr$pop), big.mark=","), "\n")

tr$area <- as.numeric(st_area(tr))
inter <- suppressWarnings(st_intersection(st_make_valid(tr), cov))
inter$covered <- as.numeric(st_area(inter))
cv <- inter |> st_drop_geometry() |> group_by(geoid) |>
  summarise(covered=sum(covered), .groups="drop")
tr2 <- tr |> st_drop_geometry() |> left_join(cv, by="geoid") |>
  mutate(covered=ifelse(is.na(covered),0,covered), frac=pmin(covered/area,1))

pw <- sum(tr2$pop * tr2$frac)/sum(tr2$pop)
cat(sprintf("\nPOPULATION-WEIGHTED coverage (our calc): %.2f%% of residents within 400m\n", 100*pw))
cat(sprintf("LAND-AREA coverage:                      %.2f%%\n",
            100*sum(tr2$covered)/sum(tr2$area)))
cat("NYC Council published figure:            49.42% of residents (Dec 2025)\n")
cat(sprintf("\nDifference vs Council: %+.2f pp\n", 100*pw - 49.42))
