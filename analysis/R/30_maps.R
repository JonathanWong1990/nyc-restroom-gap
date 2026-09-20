# 30_maps.R — Session 5 spatial: leaflet coverage + gap maps.
suppressMessages({library(sf); library(dplyr); library(leaflet); library(htmlwidgets)})
options(scipen=999); D <- "data_raw"; O <- "outputs"

sc  <- read.csv(file.path(D,"model_nta_scored_20260920.csv"))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  select(nta2020, geometry)
g <- nta |> inner_join(sc, by="nta2020")
cat("mapped neighbourhoods:", nrow(g), "\n")

rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv")) |>
  filter(status=="Operational", open=="Year Round", !is.na(latitude), !is.na(longitude))
cat("restrooms plotted:", nrow(rr), "\n")

## ---------- MAP 1: unmet need (model residual) ------------------------------
pal <- colorBin("YlOrRd", domain=g$resid_ratio,
                bins=c(0,0.5,0.8,1.2,1.8,2.5,4), na.color="#eeeeee")
lab <- sprintf(
  "<b>%s</b><br/>Complaints: <b>%d</b><br/>Model predicts: %.1f<br/>
   <b>Unmet-need ratio: %.2fx</b><br/>Operational restrooms: %d<br/>Subway riders/yr: %.1fM",
  g$ntaname, g$events_311, g$pred, g$resid_ratio, g$restrooms, g$subway_riders/1e6) |>
  lapply(htmltools::HTML)

m1 <- leaflet(g) |> addProviderTiles("CartoDB.Positron") |>
  setView(-73.95, 40.71, 10) |>
  addPolygons(fillColor=~pal(resid_ratio), fillOpacity=0.75, color="white",
              weight=0.6, label=lab,
              highlightOptions=highlightOptions(weight=2, color="#222", bringToFront=TRUE)) |>
  addCircleMarkers(data=rr, lng=~longitude, lat=~latitude, radius=2.5,
                   color="#1a6bb5", fillOpacity=0.85, stroke=FALSE,
                   label=~facility_name, group="Operational restrooms") |>
  addLegend(pal=pal, values=~resid_ratio, title="Unmet need<br/>(actual ÷ predicted)",
            position="bottomright") |>
  addLayersControl(overlayGroups="Operational restrooms",
                   options=layersControlOptions(collapsed=FALSE))
saveWidget(m1, file.path(normalizePath(O),"map1_unmet_need.html"), selfcontained=FALSE)
cat("[ok] map1_unmet_need.html\n")

## ---------- MAP 2: supply coverage vs transit demand ------------------------
rr_sf <- st_as_sf(rr, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)
cov   <- st_union(st_buffer(rr_sf, 400/0.3048)) |> st_transform(4326)

mta <- read.csv(file.path(D,"mta_ak4z-sape_monthly_20260920.csv"))
l12 <- sort(unique(mta$month), decreasing=TRUE)[1:12]
stn <- mta |> filter(month %in% l12) |> group_by(station_complex_id, station_complex) |>
  summarise(r=sum(ridership), lat=first(latitude), lon=first(longitude), .groups="drop")
stn_sf <- st_as_sf(stn, coords=c("lon","lat"), crs=4326) |> st_transform(2263)
stn$unserved <- as.numeric(st_distance(stn_sf, rr_sf) |> apply(1,min)) > (400/0.3048)
cat("stations with no restroom within 400m:", sum(stn$unserved), "/", nrow(stn), "\n")

m2 <- leaflet() |> addProviderTiles("CartoDB.DarkMatter") |> setView(-73.95,40.71,11) |>
  addPolygons(data=cov, fillColor="#2ca25f", fillOpacity=0.35, weight=0,
              group="5-min walk coverage") |>
  addCircleMarkers(data=stn[!stn$unserved,], lng=~lon, lat=~lat,
                   radius=~pmax(3, sqrt(r)/900), color="#6fd08c", stroke=FALSE,
                   fillOpacity=0.7, label=~station_complex, group="Station: served") |>
  addCircleMarkers(data=stn[stn$unserved,], lng=~lon, lat=~lat,
                   radius=~pmax(3, sqrt(r)/900), color="#ff4d4d", stroke=FALSE,
                   fillOpacity=0.9,
                   label=~sprintf("%s — %.1fM riders/yr, NO restroom within 400m",
                                  station_complex, r/1e6),
                   group="Station: NO restroom within 400m") |>
  addLegend(colors=c("#2ca25f","#6fd08c","#ff4d4d"),
            labels=c("5-min walk of a restroom","Station served","Station unserved (size = ridership)"),
            position="bottomright") |>
  addLayersControl(overlayGroups=c("5-min walk coverage","Station: served",
                                   "Station: NO restroom within 400m"),
                   options=layersControlOptions(collapsed=FALSE))
saveWidget(m2, file.path(normalizePath(O),"map2_coverage_gap.html"), selfcontained=FALSE)
cat("[ok] map2_coverage_gap.html\n")

## ---------- coverage statistic for the deck ---------------------------------
covp <- st_transform(cov, 2263)
g2 <- st_transform(g, 2263) |> mutate(
  area=as.numeric(st_area(geometry)),
  covered=as.numeric(st_area(st_intersection(geometry, covp))))
cat(sprintf("\nCITYWIDE: %.1f%% of residential NTA land is within a 5-min walk of an operational restroom\n",
            100*sum(g2$covered)/sum(g2$area)))
top <- g2 |> st_drop_geometry() |> mutate(cov_pct=100*covered/area) |>
  arrange(desc(resid_ratio)) |> head(10)
cat("\nCoverage in the 10 highest-unmet-need neighbourhoods:\n")
print(top |> transmute(neighbourhood=substr(ntaname,1,34), ratio=round(resid_ratio,2),
                       coverage_pct=round(cov_pct,1), restrooms), row.names=FALSE)
