suppressMessages({library(dplyr)})
options(scipen=999); D <- "data_raw"
m  <- read.csv(file.path(D,"pipInspectionsMaster_yg3y-7juh_20260920.csv"))
cs <- read.csv(file.path(D,"pipInspections_mp8v-wjtf_20260920.csv"))
j <- cs |> inner_join(m, by=c("inspectionid"="inspection_id")) |>
  mutate(date=as.Date(substr(date,1,10)),
         closed_flag = nzchar(trimws(closed)))
cat("restroom inspections:", nrow(j), " prop_ids:", n_distinct(j$prop_id), "\n")
cat("inspections flagged closed/construction:", sum(j$closed_flag),
    sprintf(" (%.1f%%)\n\n", 100*mean(j$closed_flag)))

s <- j |> filter(!is.na(date)) |> arrange(prop_id, date) |> group_by(prop_id) |>
  mutate(n_insp=n(), prev=lag(closed_flag),
         switch = !is.na(prev) & prev != closed_flag) |> ungroup()
cat("prop_ids with >=8 inspections:", n_distinct(s$prop_id[s$n_insp>=8]), "\n")
sw <- s |> filter(switch, n_insp>=8)
cat("switch events:", nrow(sw), " across", n_distinct(sw$prop_id), "prop_ids\n")
cat("  -> into closed:", sum(sw$closed_flag), "   -> into open:", sum(!sw$closed_flag), "\n")
cat("\nevents per year:\n"); print(table(format(sw$date,"%Y")))
cat("\nswitches per prop_id:\n"); print(sw |> count(prop_id) |> count(n, name="props") |> head(6))

# CLEAN treatment: a prop that is closed for a spell then reopens, once
spell <- s |> filter(n_insp>=8) |> group_by(prop_id) |>
  summarise(n_sw=sum(switch), ever_closed=any(closed_flag), .groups="drop")
cat("\nprops with exactly 2 switches (close then reopen):", sum(spell$n_sw==2), "\n")
cat("props with exactly 1 switch:", sum(spell$n_sw==1), "\n")
cat("props never closed:", sum(!spell$ever_closed), " <- potential controls\n")

# inspection cadence: how often is a site visited?
cad <- j |> filter(!is.na(date)) |> group_by(prop_id) |> arrange(date) |>
  summarise(n=n(), span_yr=as.numeric(diff(range(date)))/365.25, .groups="drop") |>
  filter(n>=8) |> mutate(per_yr=n/pmax(span_yr,0.1))
cat("\nmedian inspections/yr at >=8-inspection sites:", round(median(cad$per_yr),1),
    " median span:", round(median(cad$span_yr),1), "yr\n")
