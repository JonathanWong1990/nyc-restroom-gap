# 60_cost_layer.R — Stage 2: WHICH intervention, at what cost, for the high-need shortlist.
# Costs are REAL, from NYC Parks Capital Tracker + documented NYCEDC modular pilot.
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"

sc  <- read.csv(file.path(D,"model_nta_investment_20260920.csv"))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> select(nta2020)

## ---- coverage % of each NTA within a 5-min walk ---------------------------
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv")) |>
  filter(status=="Operational", open=="Year Round", !is.na(latitude), !is.na(longitude))
rr_sf <- st_as_sf(rr, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)
cov <- st_union(st_buffer(rr_sf, 400/0.3048))
nta$area <- as.numeric(st_area(nta))
ii <- suppressWarnings(st_intersection(st_make_valid(nta), cov))
ii$cv <- as.numeric(st_area(ii))
cvg <- ii |> st_drop_geometry() |> group_by(nta2020) |> summarise(cv=sum(cv), .groups="drop")
geo <- nta |> st_drop_geometry() |> left_join(cvg, by="nta2020") |>
  mutate(coverage = 100*ifelse(is.na(cv),0,cv)/area) |> select(nta2020, coverage)

## ---- hours: how long is the average facility actually open? ---------------
ph <- read.csv(file.path(D,"parsed_hours_20260920.csv")) |> filter(parsed, is_open)
fac <- ph |> group_by(facility_id) |>
  summarise(mean_h = mean(pmax(close_hour-open_hour,0)),
            late = any(close_hour >= 22), .groups="drop")
rr$facility_id <- seq_len(nrow(read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"))))[
  read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"))$status=="Operational" &
  read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"))$open=="Year Round"]
rr2 <- st_as_sf(rr, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta |> select(nta2020), join=st_within) |> st_drop_geometry() |>
  left_join(fac, by="facility_id")
hrs <- rr2 |> filter(!is.na(nta2020)) |> group_by(nta2020) |>
  summarise(med_hours = median(mean_h, na.rm=TRUE),
            n_late = sum(late, na.rm=TRUE), .groups="drop")

## ---- condition: latest PIP rating for restrooms in each NTA ---------------
mm <- read.csv(file.path(D,"pipInspectionsMaster_yg3y-7juh_20260920.csv"))
cs <- read.csv(file.path(D,"pipInspections_mp8v-wjtf_20260920.csv"))
pp <- cs |> inner_join(mm, by=c("inspectionid"="inspection_id")) |>
  mutate(date=as.Date(substr(date,1,10)),
         park=sub("-ZN.*$","",toupper(trimws(prop_id)))) |>
  filter(!is.na(date), date >= as.Date("2022-01-01"))
pk <- readRDS(file.path(D,"parksprops_sf_20260920.rds")) |> st_transform(2263) |>
  mutate(park=toupper(trimws(gispropnum)))
pk <- pk[!duplicated(pk$park),]
pkn <- st_join(st_point_on_surface(st_make_valid(pk |> select(park))), nta |> select(nta2020),
               join=st_within) |> st_drop_geometry()
cond <- pp |> inner_join(pkn, by="park") |> filter(!is.na(nta2020)) |>
  group_by(nta2020) |>
  summarise(pct_unacceptable = 100*mean(overall_condition=="U", na.rm=TRUE),
            n_insp=n(), .groups="drop") |> filter(n_insp >= 5)

d <- sc |> left_join(geo,  by="nta2020") |> left_join(hrs, by="nta2020") |>
  left_join(cond, by="nta2020")

## ---- decision rule ---------------------------------------------------------
CAP <- c(new_build=3793000, modular=1200000, reconstruction=1152500, component=60500, hours=0)
d <- d |> mutate(
  intervention = case_when(
    restrooms == 0 | coverage < 35            ~ "Build new / modular unit",
    !is.na(pct_unacceptable) & pct_unacceptable >= 20 ~ "Reconstruct or repair",
    !is.na(med_hours) & med_hours < 9         ~ "Extend operating hours",
    n_late == 0 | is.na(n_late)               ~ "Extend operating hours",
    TRUE                                       ~ "Monitor / already served"),
  capex = case_when(
    intervention=="Build new / modular unit" ~ CAP["modular"],
    intervention=="Reconstruct or repair"    ~ CAP["component"],
    intervention=="Extend operating hours"   ~ CAP["hours"],
    TRUE ~ NA_real_),
  excess = pmax(events_311 - pred, 0))

short <- d |> filter(resid_ratio >= 1.5) |> arrange(desc(resid_ratio))
cat("SHORTLIST (unmet-need ratio >= 1.5):", nrow(short), "neighbourhoods\n")
cat("Stage-2 discipline: costing ONLY these, not all 197.\n\n")
print(short |> transmute(neighbourhood=substr(ntaname,1,30), ratio=round(resid_ratio,2),
        excess=round(excess), restrooms, cover=round(coverage), hrs=round(med_hours,1),
        bad_pct=round(pct_unacceptable), action=intervention,
        capex=ifelse(is.na(capex),"-",format(capex, big.mark=","))) |> head(18), row.names=FALSE)

cat("\n=== Intervention mix across the shortlist ===\n")
print(short |> count(intervention, name="neighbourhoods") |> arrange(desc(neighbourhoods)),
      row.names=FALSE)
cat("\n=== Cost-effectiveness: $ per excess complaint addressed (lower = better) ===\n")
print(short |> filter(!is.na(capex), excess > 0) |>
  mutate(cost_per = capex/excess) |> arrange(cost_per) |>
  transmute(neighbourhood=substr(ntaname,1,30), action=intervention,
            capex=format(capex,big.mark=","), excess=round(excess),
            cost_per_excess=format(round(cost_per), big.mark=",")) |> head(12), row.names=FALSE)
tot <- sum(short$capex, na.rm=TRUE)
cat(sprintf("\nTOTAL CapEx to address the whole shortlist: $%s\n", format(tot, big.mark=",")))
cat(sprintf("For comparison, ONE traditional new-build comfort station: $%s\n",
            format(CAP["new_build"], big.mark=",")))
write.csv(d, file.path(D,"model_nta_interventions_20260920.csv"), row.names=FALSE)
