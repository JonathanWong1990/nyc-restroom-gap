# 11_benchmark.R — the one-liner rules any model must beat.
suppressMessages({library(sf); library(dplyr)})
options(scipen=999)
D <- "data_raw"
sp  <- readRDS(file.path(D,"model_spatial_20260920.rds"))
tab <- read.csv(file.path(D,"model_nta_table_20260920.csv"))
tab$oneliner <- NULL   # idempotent: drop any column written by a previous run

FT400 <- 400/0.3048   # EPSG:2263 is US survey feet
rr  <- sp$rr  |> filter(!is.na(nta2020))
stn <- sp$stn |> filter(!is.na(nta2020))

# nearest operational restroom to each subway complex
d <- st_distance(stn, rr)
stn$nearest_ft <- apply(d, 1, min)
stn$unserved   <- stn$nearest_ft > FT400
cat("subway complexes:", nrow(stn),
    " with NO restroom within 400m:", sum(stn$unserved),
    sprintf(" (%.1f%%)\n", 100*mean(stn$unserved)))
cat("median distance to nearest restroom:", round(median(stn$nearest_ft)*0.3048), "m\n\n")

ol <- stn |> st_drop_geometry() |> filter(unserved) |>
  group_by(nta2020) |> summarise(oneliner = sum(ridership), .groups="drop")
tab <- tab |> left_join(ol, by="nta2020") |>
  mutate(oneliner = ifelse(is.na(oneliner), 0, oneliner))

# candidate simple rules, all scored against OBSERVED complaints
rules <- list(
  "ONE-LINER: riders at stations w/o restroom <400m" = tab$oneliner,
  "subway ridership (all stations)"                  = tab$subway_riders,
  "workplace jobs"                                   = tab$jobs,
  "resident population"                              = tab$pop_total,
  "jobs per sq mi"                                   = tab$jobs_density,
  "hotels"                                           = tab$hotels,
  "restrooms (negative = fewer is worse)"            = -tab$restrooms
)
y <- tab$events_311
top <- function(x, k=20) order(x, decreasing=TRUE)[1:k]
actual20 <- top(y)

cat(sprintf("%-52s %8s %8s %10s\n","RULE","Spearman","Pearson","top20 hit"))
res <- sapply(names(rules), function(nm){
  x <- rules[[nm]]
  s <- cor(x, y, method="spearman"); p <- cor(x, y)
  hit <- length(intersect(top(x), actual20))
  cat(sprintf("%-52s %8.3f %8.3f %7d/20\n", nm, s, p, hit))
  c(spearman=s, hit=hit)
})

cat("\nTop 10 by the ONE-LINER:\n")
print(tab |> arrange(desc(oneliner)) |>
        transmute(ntaname=substr(ntaname,1,42), riders_unserved=round(oneliner/1e6,1),
                  complaints=events_311, restrooms) |> head(10), row.names=FALSE)
cat("\nTop 10 by ACTUAL complaints:\n")
print(tab |> arrange(desc(events_311)) |>
        transmute(ntaname=substr(ntaname,1,42), complaints=events_311,
                  restrooms, jobs_k=round(jobs/1000)) |> head(10), row.names=FALSE)

write.csv(tab, file.path(D,"model_nta_benchmark_20260920.csv"), row.names=FALSE)
