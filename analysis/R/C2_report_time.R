# C2_report_time.R — is the 18:00 peak real, or just when people are free to phone?
# Test 1: compare against other 311 complaint types (same calling behaviour, different acts).
# Test 2: compare against police summonses, which are timestamped by an officer on scene.
suppressMessages(library(dplyr)); options(scipen=999); D <- "data_raw"

hr <- function(x) as.integer(substr(x, 12, 13))
prof <- function(h, lab){
  tb <- table(factor(h, levels=0:23)); p <- 100*tb/sum(tb)
  cat(sprintf("%-26s peak %02d:00   evening 18-23 %4.1f%%   overnight 0-5 %4.1f%%\n",
      lab, as.integer(names(which.max(tb))), sum(p[as.character(18:23)]), sum(p[as.character(0:5)])))
  invisible(as.numeric(p))
}

u <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"), stringsAsFactors=FALSE) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"))
cat("=== TEST 1: does every 311 complaint type peak at the same hour? ===\n")
pu <- prof(hr(u$created_date), "Urinating in Public")
d2 <- read.csv(file.path(D,"nyc311_dirtycondition_erm2-nwe9_20260920.csv"), stringsAsFactors=FALSE)
pd <- prof(hr(d2$created_date), "Dirty Condition (DSNY)")

cat("\n=== TEST 2: officer-observed summonses, timestamped on scene ===\n")
o <- read.csv(file.path(D,"nypd_oath_urination_hxbk-grd3_20260920.csv"), stringsAsFactors=FALSE)
tcol <- grep("occur_date|date", names(o), value=TRUE)[1]
oh <- hr(o[[tcol]])
if (all(is.na(oh)) || length(unique(na.omit(oh)))<3) {
  cat("summons timestamps carry no usable hour component — test 2 not available\n")
} else {
  ps <- prof(oh, "Public urination summonses")
  cat(sprintf("\ncorrelation of hourly shape, complaints vs summonses: %.3f\n", cor(pu, ps)))
}
cat(sprintf("correlation of hourly shape, urination vs dirty-condition: %.3f\n", cor(pu, pd)))
cat("\nA high correlation with other complaint types would mean we are measuring calling habits.\n")
