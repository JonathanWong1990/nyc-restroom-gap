# 70_audit_checks.R — two checks the adversarial review said were missing.
suppressMessages({library(dplyr)})
options(scipen=999); D <- "data_raw"
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"),
              stringsAsFactors=FALSE) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
         !is.na(latitude), !is.na(longitude)) |>
  mutate(ts = as.POSIXct(created_date, format="%Y-%m-%dT%H:%M:%S", tz="UTC"),
         ym = format(ts,"%Y-%m"), hour = as.integer(format(ts,"%H"))) |>
  distinct(incident_address, ym, .keep_all=TRUE)
cat("deduped events:", nrow(e), "\n\n")

## ---- CHECK 1: is this a nocturnal phenomenon? -----------------------------
cat("=== TIME OF DAY ===\n")
h <- table(factor(e$hour, levels=0:23))
for(b in list(c(0,5,"00:00-05:59 overnight"), c(6,11,"06:00-11:59 morning"),
              c(12,17,"12:00-17:59 afternoon"), c(18,23,"18:00-23:59 evening"))){
  lo <- as.integer(b[1]); hi <- as.integer(b[2])
  n <- sum(h[as.character(lo:hi)])
  cat(sprintf("  %-22s %5d  %5.1f%%\n", b[3], n, 100*n/nrow(e)))
}
cat("\n  peak hours:\n")
top <- sort(h, decreasing=TRUE)[1:6]
for(i in seq_along(top)) cat(sprintf("    %02d:00  %4d\n", as.integer(names(top)[i]), top[i]))

# share of complaints at times when almost nothing is open
rrall <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"))
opid <- which(rrall$status=="Operational" & rrall$open=="Year Round")
ph <- read.csv(file.path(D,"parsed_hours_20260920.csv")) |>
  filter(parsed, is_open, facility_id %in% opid)
open_at <- sapply(0:23, function(hh) sum(ph$open_hour <= hh & ph$close_hour > hh) / 7)
cat("\n  facilities open, by hour (approx, averaged over days):\n")
for(hh in c(2,6,9,12,15,18,21,23)) cat(sprintf("    %02d:00  %5.0f of 843\n", hh, open_at[hh+1]))
night <- sum(h[as.character(c(22,23,0,1,2,3,4,5))])
cat(sprintf("\n  complaints 22:00-05:59: %d (%.1f%%), when ~%.0f facilities are open\n",
            night, 100*night/nrow(e), mean(open_at[c(23,24,1,2,3,4,5,6)])))

## ---- CHECK 2: phone-only sensitivity (reporting-channel bias) -------------
cat("\n=== REPORTING CHANNEL ===\n")
print(sort(table(e$open_data_channel_type), decreasing=TRUE))
xw <- read.csv(file.path(D,"lookup_tract_to_nta_20260920.csv"))  # not used for join; NTA via scored file
sc <- read.csv(file.path(D,"model_nta_scored_20260920.csv"))

# assign events to NTA using the same spatial join as before
suppressMessages(library(sf))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> select(nta2020)
esf <- st_as_sf(e, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020))

all_n   <- esf |> count(nta2020, name="all")
phone_n <- esf |> filter(open_data_channel_type=="PHONE") |> count(nta2020, name="phone")
cmp <- sc |> select(nta2020, ntaname, pred, resid_ratio) |>
  left_join(all_n, by="nta2020") |> left_join(phone_n, by="nta2020") |>
  mutate(all=ifelse(is.na(all),0,all), phone=ifelse(is.na(phone),0,phone),
         ratio_all   = all/pmax(pred,0.01),
         ratio_phone = phone/pmax(pred*mean(phone)/mean(all),0.01))
cat(sprintf("\nphone share of all events: %.1f%%\n", 100*sum(cmp$phone)/sum(cmp$all)))
cat(sprintf("Spearman(all-based ranking, phone-only ranking) = %.3f\n",
            cor(cmp$ratio_all, cmp$ratio_phone, method="spearman")))
t10a <- cmp$nta2020[order(-cmp$ratio_all)][1:10]
t10p <- cmp$nta2020[order(-cmp$ratio_phone)][1:10]
cat(sprintf("top-10 overlap between the two rankings: %d of 10\n", length(intersect(t10a,t10p))))
cat("\nDo the published top 6 survive a phone-only ranking?\n")
pub <- c("Brighton Beach","East Elmhurst","East Flatbush-Rugby","East Harlem (North)",
         "Williamsbridge-Olinville","Astoria (East)-Woodside (North)")
rk <- cmp |> arrange(desc(ratio_phone)) |> mutate(rank_phone=row_number()) |>
  arrange(desc(ratio_all)) |> mutate(rank_all=row_number())
print(rk |> filter(ntaname %in% pub) |>
  transmute(neighbourhood=substr(ntaname,1,32), rank_all, rank_phone,
            all, phone), row.names=FALSE)
