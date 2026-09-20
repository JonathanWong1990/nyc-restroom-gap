# 13_did_panel.R — build park x month panel: closure status vs nearby 311 complaints
suppressMessages({library(sf); library(dplyr); library(tidyr)})
options(scipen=999); D <- "data_raw"
RAD_FT <- 500/0.3048

## --- parks with usable inspection history -----------------------------------
m  <- read.csv(file.path(D,"pipInspectionsMaster_yg3y-7juh_20260920.csv"))
cs <- read.csv(file.path(D,"pipInspections_mp8v-wjtf_20260920.csv"))
insp <- cs |> inner_join(m, by=c("inspectionid"="inspection_id")) |>
  mutate(date=as.Date(substr(date,1,10)), closed_flag=nzchar(trimws(closed)),
         park=sub("-ZN.*$","",toupper(trimws(prop_id)))) |>
  filter(!is.na(date)) |> group_by(prop_id) |> filter(n()>=8) |> ungroup()

## --- park geometry ----------------------------------------------------------
pk <- readRDS(file.path(D,"parksprops_sf_20260920.rds"))
pk <- st_transform(pk, 2263) |> mutate(park=toupper(trimws(gispropnum)))
pk <- pk[!duplicated(pk$park), ]
keep <- intersect(unique(insp$park), pk$park)
cat("parks matched to geometry:", length(keep), "\n")
pkk <- pk |> filter(park %in% keep) |> select(park)
buf <- st_buffer(pkk, RAD_FT)

## --- 311 outcome ------------------------------------------------------------
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
e <- e |> filter(complaint_type=="Urinating in Public",
                 location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
                 !is.na(latitude), !is.na(longitude)) |>
  mutate(date=as.Date(substr(created_date,1,10)), ym=format(date,"%Y-%m")) |>
  distinct(incident_address, ym, .keep_all=TRUE)
cat("311 events (deduped, coords):", nrow(e), "\n")
esf <- st_as_sf(e, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)

hit <- st_join(esf, buf, join=st_within, left=FALSE)
cat("events falling within 500m of a study park:", nrow(hit),
    " distinct parks hit:", n_distinct(hit$park), "\n")

## --- monthly panel ----------------------------------------------------------
months <- format(seq(as.Date("2020-01-01"), as.Date("2026-06-01"), by="month"), "%Y-%m")
panel <- expand_grid(park=keep, ym=months)

cnt <- hit |> st_drop_geometry() |> count(park, ym, name="complaints")
panel <- panel |> left_join(cnt, by=c("park","ym")) |>
  mutate(complaints=replace_na(complaints,0L))

# carry-forward closure status from inspections to each month
st_hist <- insp |> group_by(park, date) |>
  summarise(closed=as.integer(any(closed_flag)), .groups="drop") |> arrange(park, date)
status_for <- function(p, mth){
  h <- st_hist[st_hist$park==p, ]
  if(!nrow(h)) return(NA_integer_)
  d <- as.Date(paste0(mth,"-01"))
  idx <- findInterval(d, h$date)
  ifelse(idx==0, NA_integer_, h$closed[pmax(idx,1)])
}
sh <- split(st_hist, st_hist$park)
panel$closed <- unlist(lapply(seq_len(nrow(panel)), function(i){
  h <- sh[[panel$park[i]]]
  if(is.null(h)) return(NA_integer_)
  idx <- findInterval(as.Date(paste0(panel$ym[i],"-01")), h$date)
  if(idx==0) NA_integer_ else h$closed[idx]
}))
panel <- panel |> filter(!is.na(closed))
cat("panel rows:", nrow(panel), " parks:", n_distinct(panel$park),
    " closed-months:", sum(panel$closed), sprintf(" (%.1f%%)\n", 100*mean(panel$closed)))
cat("mean complaints/park-month:", round(mean(panel$complaints),3),
    " share zero:", sprintf("%.1f%%\n", 100*mean(panel$complaints==0)))

# keep parks with any variation in closure AND any complaints (FE needs both)
vary <- panel |> group_by(park) |>
  summarise(v=n_distinct(closed), tot=sum(complaints), .groups="drop")
cat("parks with closure variation:", sum(vary$v>1),
    " of which any complaints:", sum(vary$v>1 & vary$tot>0), "\n")
saveRDS(panel, file.path(D,"did_panel_20260920.rds"))
write.csv(vary, file.path(D,"did_park_variation_20260920.csv"), row.names=FALSE)
