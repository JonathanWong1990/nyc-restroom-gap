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

## ---- WHY WE DO NOT USE THE PARK-WIDE PLACEBO -------------------------------
## The obvious placebo is park-wide condition: same inspector, same visit, a
## different outcome. Pooled across all parks it looks flat, which would appear
## to clear the finding. It does not: the flatness is two opposite movements
## cancelling. Parks WITHOUT a comfort station improve while parks WITH one get
## worse, and site condition is not independent of restroom condition anyway.
## The defensible placebo is the internal one above (litter/graffiti vs structural).
cat("\n=== PARK-WIDE PLACEBO: flat in aggregate, not flat underneath ===\n")
mas[, date := as.IDate(date)][, yr := year(date)][, doy := as.integer(format(date,"%j"))]
has_cs <- unique(ins$inspection_id)
mas[, has_cs := inspection_id %in% has_cs]
pw <- mas[doy <= 179 & yr >= 2022 & overall_condition %in% c("A","U")]
cat("pooled over ALL park inspections:\n")
print(pw[, .(n=.N, site_fail=round(mean(overall_condition=="U"),4)), by=yr][order(yr)])
cat("\nsplit by whether the park HAS a comfort station:\n")
print(pw[, .(n=.N, site_fail=round(mean(overall_condition=="U"),4)),
         by=.(yr, has_cs)][order(has_cs, yr)])
cat("\nis site condition independent of restroom condition?\n")
j <- merge(ins[, .(inspection_id, cs_overall_condition)],
           mas[, .(inspection_id, overall_condition)], by="inspection_id")
j <- j[cs_overall_condition %in% c("A","U") & overall_condition %in% c("A","U")]
cat(sprintf("  P(site fails | restroom fails) = %.3f   P(site fails | restroom ok) = %.3f\n",
    mean(j[cs_overall_condition=="U"]$overall_condition=="U"),
    mean(j[cs_overall_condition=="A"]$overall_condition=="U")))
cat("  -> not independent, so park-wide condition is a contaminated placebo.\n")

## ---- the within-inspector sub-scores, for the seven who rated both years ----
cat("\n=== SUB-SCORES FOR THE SEVEN INSPECTORS PRESENT IN BOTH 2024 AND 2026 ===\n")
d7 <- merge(ins, mas[, .(inspection_id, date, inspector)], by="inspection_id")
d7[, yr := year(as.IDate(date))][, doy := as.integer(format(as.IDate(date),"%j"))]
d7 <- d7[doy <= 179]
b7 <- intersect(d7[yr==2024 & cs_structural %in% c("A","U"), unique(inspector)],
                d7[yr==2026 & cs_structural %in% c("A","U"), unique(inspector)])
for (c in c("cs_litter","cs_graffiti","cs_amenities","cs_structural")) {
  s <- d7[inspector %in% b7 & yr %in% c(2024,2026) & get(c) %in% c("A","U"),
          .(f=round(mean(get(c)=="U"),3)), by=yr][order(yr)]
  cat(sprintf("%-14s %s\n", sub("cs_","",c), paste(sprintf("%d:%.3f", s$yr, s$f), collapse="  ")))
}
