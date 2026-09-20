# 90_two_signals.R — does a second, independent measure agree with 311?
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> select(nta2020)
sc <- read.csv(file.path(D,"model_nta_scored_20260920.csv"))

o <- read.csv(file.path(D,"nypd_oath_urination_hxbk-grd3_20260920.csv"), stringsAsFactors=FALSE)
dcol <- grep("date", names(o), ignore.case=TRUE, value=TRUE)[1]
o$lat <- suppressWarnings(as.numeric(o[[grep("^lat",names(o),ignore.case=TRUE)[1]]]))
o$lon <- suppressWarnings(as.numeric(o[[grep("^lon|^lng",names(o),ignore.case=TRUE)[1]]]))
o <- o |> filter(!is.na(lat), !is.na(lon)) |>
  mutate(ym = substr(.data[[dcol]],1,7), klat=round(lat,5), klon=round(lon,5))
cat("OATH urination summonses:", nrow(o), "\n")
osf <- st_as_sf(o, coords=c("lon","lat"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020))
cat("assigned to an NTA:", nrow(osf), sprintf(" (%.1f%%)\n", 100*nrow(osf)/nrow(o)))
oath <- osf |> distinct(klat, klon, ym, nta2020) |> count(nta2020, name="oath")
cat("de-duplicated to coord-month:", sum(oath$oath), "events\n\n")

# 311 restricted to the SAME window for a fair comparison
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv")) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
         !is.na(latitude), !is.na(longitude)) |>
  mutate(d=as.Date(substr(created_date,1,10)), ym=format(d,"%Y-%m")) |>
  filter(d >= as.Date("2023-01-01"), d <= as.Date("2026-06-30")) |>
  distinct(incident_address, ym, .keep_all=TRUE)
esf <- st_as_sf(e, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020)) |>
  count(nta2020, name="c311")
cat("311 events in the SAME window:", sum(esf$c311), "\n\n")

d <- sc |> select(nta2020, ntaname, pop_total, resid_ratio) |>
  left_join(oath, by="nta2020") |> left_join(esf, by="nta2020") |>
  mutate(oath=ifelse(is.na(oath),0,oath), c311=ifelse(is.na(c311),0,c311))
cat("=== DENSITY COMPARISON (same 3.5-year window, 197 NTAs) ===\n")
cat(sprintf("311  : total %5d  median %3.0f  zeros %2d\n", sum(d$c311), median(d$c311), sum(d$c311==0)))
cat(sprintf("OATH : total %5d  median %3.0f  zeros %2d   -> %.1fx the events\n",
            sum(d$oath), median(d$oath), sum(d$oath==0), sum(d$oath)/sum(d$c311)))
cat(sprintf("\nAgreement between the two measures: Spearman %.3f\n",
            cor(d$oath, d$c311, method="spearman")))
t25 <- function(x) d$nta2020[order(-x)][1:25]
cat(sprintf("top-10 overlap: %d/10   top-25 overlap: %d/25\n",
  length(intersect(d$nta2020[order(-d$oath)][1:10], d$nta2020[order(-d$c311)][1:10])),
  length(intersect(t25(d$oath), t25(d$c311)))))
cat("\n=== NEIGHBOURHOODS IN THE TOP 25 OF *BOTH* (need visible to both mechanisms) ===\n")
both <- intersect(t25(d$oath), t25(d$c311))
print(d |> filter(nta2020 %in% both) |> arrange(desc(oath+c311)) |>
  transmute(neighbourhood=substr(ntaname,1,34), summonses=oath, complaints=c311,
            unmet_need_ratio=round(resid_ratio,2)), row.names=FALSE)
write.csv(d, file.path(D,"model_two_signals_20260920.csv"), row.names=FALSE)
