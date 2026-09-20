# 12_did_feasibility.R — can we build a staggered DiD? Diagnose BEFORE modelling.
suppressMessages({library(dplyr)})
options(scipen=999)
D <- "data_raw"
m  <- read.csv(file.path(D,"pipInspectionsMaster_yg3y-7juh_20260920.csv"))
cs <- read.csv(file.path(D,"pipInspections_mp8v-wjtf_20260920.csv"))

cat("master rows:", nrow(m), " cs-module rows:", nrow(cs), "\n")
cat("cs joins to master on inspection_id:",
    sum(cs$inspectionid %in% m$inspection_id), "/", nrow(cs), "\n")
cat("master inspection_id unique:", !any(duplicated(m$inspection_id)), "\n\n")

j <- cs |> inner_join(m, by=c("inspectionid"="inspection_id"))
j$date <- as.Date(substr(j$date,1,10))
cat("restroom inspections:", nrow(j), " date range:", format(min(j$date,na.rm=TRUE)),
    "->", format(max(j$date,na.rm=TRUE)), "\n")
cat("distinct csnumber:", n_distinct(j$csnumber), " distinct prop_id:", n_distinct(j$prop_id), "\n")
cat("\n'closed' values:\n"); print(table(j$closed, useNA="ifany"))

# --- transitions per comfort station ---
j2 <- j |> filter(!is.na(date), !is.na(closed), closed!="") |>
  mutate(is_closed = closed %in% c("Y","Yes","true","TRUE","T","1")) |>
  arrange(csnumber, date)
cat("\nusable inspections:", nrow(j2), "\n")

tr <- j2 |> group_by(csnumber) |>
  filter(n() >= 6) |>
  mutate(prev = lag(is_closed), switch = !is.na(prev) & prev != is_closed) |>
  ungroup()
cat("stations with >=6 inspections:", n_distinct(tr$csnumber), "\n")
sw <- tr |> filter(switch)
cat("total switch events:", nrow(sw), " across", n_distinct(sw$csnumber), "stations\n")
cat("  closures (open->closed):", sum(sw$is_closed), "\n")
cat("  reopenings (closed->open):", sum(!sw$is_closed), "\n")
cat("\nswitch events by year:\n"); print(table(format(sw$date,"%Y")))

# how many stations switch exactly once (cleanest treatment)?
once <- sw |> count(csnumber) |> count(n, name="stations")
cat("\nswitches per station:\n"); print(head(once,8))

# --- geolocation: prop_id -> parks gispropnum ---
pk <- read.csv(file.path(D,"parksprops_enfh-gkve_20260920.csv"))
gcol <- grep("gispropnum", names(pk), ignore.case=TRUE, value=TRUE)[1]
cat("\nparks rows:", nrow(pk), " key col:", gcol, "\n")
strip <- function(x) sub("-ZN.*$","",toupper(trimws(x)))
u <- unique(j2$prop_id)
cat("prop_id raw match:", sum(toupper(u) %in% toupper(pk[[gcol]])), "/", length(u), "\n")
cat("prop_id stripped match:", sum(strip(u) %in% toupper(pk[[gcol]])), "/", length(u), "\n")
cat("cardinality prop_id -> park (stripped):\n")
print(data.frame(prop=u, park=strip(u)) |> count(park) |> count(n, name="parks") |> head(5))
