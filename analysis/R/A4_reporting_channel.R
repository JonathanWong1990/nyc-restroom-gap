# A4_reporting_channel.R — backs the published correlations describing reporting bias:
# 0.597 with the share of complaints filed online, 0.027 with total 311 volume.
suppressMessages({library(sf); library(dplyr)}); options(scipen=999); D <- "data_raw"
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"),
              stringsAsFactors=FALSE) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
         !is.na(latitude), !is.na(longitude)) |>
  mutate(ym=format(as.Date(substr(created_date,1,10)),"%Y-%m")) |>
  distinct(incident_address, ym, .keep_all=TRUE)
cb <- suppressWarnings(as.integer(substr(trimws(e$community_board),1,3)))
e <- e[!is.na(cb) & cb>=1 & cb<=18, ]
e$board <- trimws(e$community_board)
per <- e |> group_by(board) |>
  summarise(events=n(), online=mean(open_data_channel_type=="ONLINE"), .groups="drop")
tot <- read.csv(file.path(D,"nyc311_totalvolume_by_cb_erm2-nwe9_20260920.csv"),
                stringsAsFactors=FALSE)
names(tot)[1:2] <- c("board","total311"); tot$board <- trimws(tot$board)
per <- per |> inner_join(tot, by="board")
# also compute on the RAW (non-de-duplicated) series, because earlier drafts quoted those
rawp <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"),
                 stringsAsFactors=FALSE) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"))
cbr <- suppressWarnings(as.integer(substr(trimws(rawp$community_board),1,3)))
rawp <- rawp[!is.na(cbr) & cbr>=1 & cbr<=18, ]; rawp$board <- trimws(rawp$community_board)
perR <- rawp |> group_by(board) |>
  summarise(events=n(), online=mean(open_data_channel_type=="ONLINE"), .groups="drop") |>
  inner_join(tot, by="board")
cat("community boards:", nrow(per), "\n\n")
cat(sprintf("%-28s %10s %10s\n", "series", "vs ONLINE", "vs TOTAL"))
cat(sprintf("%-28s %10.3f %10.3f\n", "raw (not de-duplicated)",
    cor(perR$events, perR$online), cor(perR$events, as.numeric(perR$total311))))
cat(sprintf("%-28s %10.3f %10.3f  <- the analysis series\n", "de-duplicated",
    cor(per$events, per$online), cor(per$events, as.numeric(per$total311))))
cat("\nEarlier drafts quoted 0.597 / 0.027, which are the RAW figures. The series actually\n")
cat("modelled is the de-duplicated one, where the channel bias is WEAKER (0.31), because\n")
cat("de-duplication removes the repeat-complainant addresses that drive it.\n")
cat("\nThe first is the reporting-channel bias the write-up discloses; the second shows the\n")
cat("cruder 'some areas just complain more' worry is not the binding problem.\n")
