# A8_condition_trend.R — is NYC's EXISTING restroom stock deteriorating?
#
# The rest of this project models 311 complaints: a thin, reporting-biased proxy for an
# unobservable. The Parks Inspection Program gives something categorically better — a
# trained inspector, on a schedule, rating an observed physical condition. ~26,000 rated
# comfort-station inspections against 3,629 complaints, and no dependence on anyone
# choosing to call.
#
# Window is matched (Jan 1 - Jun 28, doy<=179) across all years because 2026 data ends
# 28 June; comparing a part-year to full years would confound season with trend.
suppressMessages({library(data.table); library(sandwich); library(lmtest)}); options(scipen=999)
D <- Sys.getenv("RESTROOM_PROJ", unset="."); dd <- file.path(D,"data_raw")
ins <- fread(file.path(dd,"pipInspections_mp8v-wjtf_20260920.csv"), showProgress=FALSE)
mas <- fread(file.path(dd,"pipInspectionsMaster_yg3y-7juh_20260920.csv"), showProgress=FALSE)
setnames(ins, "inspectionid", "inspection_id")
for (c in grep("^cs_", names(ins), value=TRUE)) ins[[c]] <- toupper(trimws(ins[[c]]))
d <- merge(ins, mas[, .(inspection_id, prop_id, date, inspector, overall_condition)],
           by="inspection_id")
d[, date := as.IDate(date)][, yr := year(date)][, doy := as.integer(format(date,"%j"))]
cat("joined", nrow(d), "of", nrow(ins), "comfort-station inspections; data end", format(max(d$date)), "\n\n")

w <- d[doy <= 179 & yr >= 2022]
cat("=== HEADLINE: restroom condition, matched Jan-Jun window ===\n")
print(w[cs_overall_condition %in% c("A","U"),
        .(rated=.N, fail_rate=round(mean(cs_overall_condition=="U"),3)), by=yr][order(yr)])
cat("\nshare of ALL inspections finding an open, acceptable restroom:\n")
print(w[, .(n=.N, acceptable=round(mean(cs_overall_condition=="A"),3),
            unrateable=round(mean(cs_overall_condition=="N"),3)), by=yr][order(yr)])

## ---- facility fixed effects: same buildings, not a changing sample ---------
cat("\n=== FACILITY FIXED EFFECTS (ref 2024), SEs clustered by facility ===\n")
r <- d[doy<=179 & yr>=2018 & cs_overall_condition %in% c("A","U")]
r[, fail := as.integer(cs_overall_condition=="U")][, yrf := relevel(factor(yr), ref="2024")]
ct <- coeftest(lm(fail ~ yrf + factor(prop_id), data=r), vcov=vcovCL, cluster=~prop_id)
print(round(ct[grep("^yrf", rownames(ct)), c(1,2,4)], 4))
cat("n =", nrow(r), " facilities =", uniqueN(r$prop_id), "\n")

## ---- THE PLACEBO: same inspector, same visit, same form -------------------
## A harsher inspector marks litter harder too. If only structural moves, the
## buildings changed, not the grader.
cat("\n=== SUB-SCORES (the internal placebo) ===\n")
for (c in c("cs_litter","cs_graffiti","cs_amenities","cs_structural")) {
  s <- w[get(c) %in% c("A","U"), .(f=round(mean(get(c)=="U"),3)), by=yr][order(yr)]
  cat(sprintf("%-14s %s\n", sub("cs_","",c), paste(sprintf("%d:%.3f", s$yr, s$f), collapse="  ")))
}

## ---- rating-drift checks ---------------------------------------------------
s <- d[doy<=179 & yr>=2022 & cs_structural %in% c("A","U")][, fail := as.integer(cs_structural=="U")]
cat("\n=== Is the rise driven by NEW inspectors? ===\n")
seen <- s[yr<=2024, unique(inspector)]; s[, newbie := !(inspector %in% seen)]
print(s[yr>=2025, .(n=.N, fail=round(mean(fail),3)), by=.(yr,newbie)][order(yr,newbie)])
cat("\n=== WITHIN-INSPECTOR change (rated in both 2024 and 2026) ===\n")
both <- intersect(s[yr==2024,unique(inspector)], s[yr==2026,unique(inspector)])
sub <- s[inspector %in% both & yr %in% c(2024,2026)]
cat("inspectors in both years:", length(both), " (thin - clustered SEs on few clusters are unreliable)\n")
print(sub[, .(n=.N, fail=round(mean(fail),3)), by=yr][order(yr)])
c2 <- coeftest(lm(fail ~ factor(yr) + factor(inspector), data=sub), vcov=vcovCL, cluster=~inspector)
cat("within-inspector 2026 effect:", round(c2["factor(yr)2026",1],4),
    " SE", round(c2["factor(yr)2026",2],4), " p", signif(c2["factor(yr)2026",4],3), "\n")
cat("\n=== Step change (rule revision) or gradual drift (decay)? ===\n")
q <- d[yr>=2023 & cs_structural %in% c("A","U")][, .(n=.N,
        fail=round(mean(cs_structural=="U"),3)), by=.(q=paste0(year(date),"Q",quarter(date)))][order(q)]
print(q)
cat("\nA guidance change gives a STEP at one date; decay gives a steady climb.\n")
