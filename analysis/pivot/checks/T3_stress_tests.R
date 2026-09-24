# T3_stress_tests.R - adversarial tests of "Parks restroom failure 8.5% (2024) -> 20.1% (2026)"
# Read-only on Restroom_Rebuild/data_raw. Writes only into this folder.
suppressMessages({library(data.table); library(sandwich); library(lmtest)}); options(scipen=999, width=200)
dd <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
ins <- fread(file.path(dd,"pipInspections_mp8v-wjtf_20260920.csv"), showProgress=FALSE)
mas <- fread(file.path(dd,"pipInspectionsMaster_yg3y-7juh_20260920.csv"), showProgress=FALSE)
setnames(ins,"inspectionid","inspection_id")
for (c in grep("^cs_",names(ins),value=TRUE)) ins[[c]] <- toupper(trimws(ins[[c]]))
mas[, date:=as.IDate(substr(date,1,10))][, yr:=year(date)][, doy:=yday(date)][, m:=month(date)]
mas[, added:=as.IDate(substr(inspaddeddate,1,10))]
d <- merge(ins, mas[, .(inspection_id, prop_id, date, yr, doy, m, inspector, inspectiontype, added, closed)], by="inspection_id")
d[, fac:=paste(prop_id, csnumber)][, boro:=substr(prop_id,1,1)]
d[, allN := cs_litter=="N"&cs_graffiti=="N"&cs_amenities=="N"&cs_structural=="N"]
d[, fail := as.integer(cs_overall_condition=="U")]
R <- d[cs_overall_condition %in% c("A","U")]           # rated
H <- function(x) x[doy<=179]
fr <- function(x) round(mean(x),3)
fe <- function(dat, extra="", ref="2024", clus=~fac) {
  dat <- copy(dat); dat[, yrf:=relevel(factor(yr), ref=ref)]
  f <- as.formula(paste("fail ~ yrf + factor(fac)", extra))
  ct <- coeftest(lm(f, data=dat), vcov=vcovCL, cluster=clus); k <- paste0("yrf2026")
  sprintf("2026 vs %s: %+.4f (SE %.4f, p=%.2g), n=%d, fac=%d", ref, ct[k,1], ct[k,2], ct[k,4], nrow(dat), uniqueN(dat$fac))
}
cat("=== 0. REPRODUCE ===\n"); print(H(R)[yr>=2022, .(n=.N, fail=fr(fail)), by=yr][order(yr)])
cat(fe(H(R)[yr>=2018]), "\n")

cat("\n=== 1. SEASONALITY ===\n")
s <- R[yr<=2026, .(H1=fr(fail[doy<=179]), nH1=sum(doy<=179), H2=fr(fail[doy>179]), FY=fr(fail)), by=yr][order(yr)]
s[yr==2026, c("H2","FY"):=NA]; print(s)
cat("month-matched: 2026 month rate minus max of same month 2022-2025\n")
mm <- dcast(R[yr>=2022 & m<=6, .(f=mean(fail)), by=.(yr,m)], m~yr, value.var="f")
mm[, gap_vs_max := round(`2026` - pmax(`2022`,`2023`,`2024`,`2025`),3)]; print(round(mm,3))
cat("FE with month-of-year FE, all months 2018-2026:\n"); cat(fe(R[yr>=2018], "+ factor(m)"), "\n")
cat("2026H1 vs 2025H2 (adjacent halves):", fr(H(R)[yr==2026]$fail), "vs", fr(R[yr==2025 & doy>179]$fail), "\n")
cat("2026H1 rank among H1 2005-2026:", rank(-s[yr>=2005]$H1)[s[yr>=2005]$yr==2026], "of", nrow(s[yr>=2005]), "; last H1 >= 0.20:", max(s[yr<2026 & H1>=0.20]$yr), "\n")

cat("\n=== 2. COMPOSITION ===\n")
print(dcast(H(d)[yr>=2018, .N, by=.(yr,inspectiontype)], yr~inspectiontype, value.var="N", fill=0))
P <- H(R)[inspectiontype=="PIP"]
cat("PIP-only H1:\n"); print(P[yr>=2022, .(n=.N, fail=fr(fail)), by=yr][order(yr)])
cat(fe(P[yr>=2018]), " [PIP only]\n")
yrs <- 2022:2026
bal <- P[yr %in% yrs, .(k=uniqueN(yr)), by=fac][k==length(yrs), fac]
B <- P[yr %in% yrs & fac %in% bal]
cat("balanced panel (PIP, rated in H1 of every year 2022-26): facilities", length(bal), "of", uniqueN(P[yr %in% yrs]$fac), "\n")
print(B[, .(n=.N, fail=fr(fail)), by=yr][order(yr)]); cat(fe(B), " [balanced]\n")
cat("facility-year collapsed (each facility weighted once per year):\n")
print(B[, .(f=mean(fail)), by=.(fac,yr)][, .(fail=fr(f)), by=yr][order(yr)])

cat("\n=== 3. RATING REGIME ===\n")
cat("3a inspectors active H1:\n"); print(H(R)[yr>=2018, .(inspectors=uniqueN(inspector)), by=yr][order(yr)])
cat("3a FE + inspector FE (2018-26 H1):", fe(H(R)[yr>=2018], "+ factor(inspector)"), "\n")
cat("3a per-inspector H1 fail, inspectors with >=20 rated in 2026H1:\n")
pi <- dcast(H(R)[yr %in% 2024:2026, .(n=.N, f=round(mean(fail),3)), by=.(inspector,yr)], inspector~yr, value.var=c("n","f"))
print(pi[n_2026>=20][order(-f_2026)])
cat("3a leave-one-inspector-out 2026H1 fail range:\n")
ii <- unique(H(R)[yr==2026]$inspector)
lo <- sapply(ii, function(i) mean(H(R)[yr==2026 & inspector!=i]$fail)); print(round(range(lo),3))
cat("3b placebo: SITE-level ratings on PIP inspections of properties with NO comfort-station row, H1\n")
cs_props <- unique(d$prop_id)
pm <- mas[doy<=179 & yr>=2018 & inspectiontype=="PIP"]
pm[, has_cs := prop_id %in% cs_props]
print(dcast(pm[overall_condition %in% c("A","U"), .(f=round(mean(overall_condition=="U"),3)), by=.(yr,has_cs)], yr~has_cs, value.var="f"))
cat("cleanliness U share (all PIP, H1):\n"); print(pm[cleanliness %in% c("A","U"), .(n=.N, f=round(mean(cleanliness=="U"),3)), by=yr][order(yr)])
cat("3b same inspectors: site-level fail at no-CS properties, 2024 vs 2026, by inspector\n")
x <- dcast(pm[!has_cs & overall_condition %in% c("A","U") & yr %in% c(2024,2026), .(f=round(mean(overall_condition=="U"),3)), by=.(inspector,yr)], inspector~yr, value.var="f"); print(x[complete.cases(x)])
cat("3c master schema: field fill-rate by year (new fields would show up here)\n")
print(mas[yr>=2018, lapply(.SD, function(v) round(mean(!is.na(v) & v!=""),3)), by=yr, .SDcols=c("safety_condition","structural_condition","inspector2","closed","visitorcount","comments")][order(yr)])
cat("3d subscore U(incl U/S) among rated, H1:\n")
for (c in c("cs_litter","cs_graffiti","cs_amenities","cs_structural")) {
  z <- H(d)[yr>=2018 & get(c) %in% c("A","U","U/S"), .(f=mean(get(c)!="A")), by=yr][order(yr)]
  cat(sprintf("%-14s %s\n", c, paste(sprintf("%d:%.3f", z$yr, z$f), collapse=" ")))}
cat("3e coupling: P(overall U | structural U or U/S), H1\n")
print(H(d)[yr>=2018 & cs_structural %in% c("U","U/S"), .(n=.N, pOverallU=fr(cs_overall_condition=="U")), by=yr][order(yr)])
cat("3f quarterly overall fail 2022-2026:\n")
print(R[yr>=2022, .(n=.N, f=fr(fail)), by=.(q=paste0(yr,"Q",quarter(date)))][order(q)])

cat("\n=== 4. ENTRY LAG ===\n")
d[, lag:=as.integer(added-date)]
print(d[yr>=2018, .(same_day=round(mean(lag==0,na.rm=T),3), max_lag=max(lag,na.rm=T), na=sum(is.na(lag))), by=yr][order(yr)])

cat("\n=== 5. UNRATED / CLOSED ===\n")
t <- H(d)[yr>=2012, .(all=.N, A=sum(cs_overall_condition=="A"), U_noSubs=sum(fail==1 & allN), U_subs=sum(fail==1 & !allN), N=sum(cs_overall_condition=="N")), by=yr][order(yr)]
t[, rated:=A+U_noSubs+U_subs][, `:=`(fail=round((U_noSubs+U_subs)/rated,3), fail_noSubs=round(U_noSubs/rated,3), fail_subs=round(U_subs/rated,3), N_share=round(N/all,3), acceptable=round(A/all,3))]
print(t); fwrite(t, "h1_decomposition.csv")
cat("fail with N counted as fail (worst case) / N dropped (headline) 2024 vs 2026:", t[yr==2024, round((all-A)/all,3)], t[yr==2026, round((all-A)/all,3)], "\n")
cat("rated-subscore failures only (U with >=1 subscore rated), FE:\n")
R2 <- copy(H(R)[yr>=2018]); R2[, fail := as.integer(fail==1 & !allN)]; cat(fe(R2), "\n")
R3 <- copy(H(R)[yr>=2018]); R3[, fail := as.integer(fail==1 & allN)]; cat("no-subscore U only, FE:", fe(R3), "\n")
cat("snow check: 2026H1 excluding Jan-Feb:", fr(H(R)[yr==2026 & m>=3]$fail), " vs 2024 same months:", fr(H(R)[yr==2024 & m>=3]$fail), "\n")

cat("\n=== 6. CONCENTRATION ===\n")
print(dcast(H(R)[yr %in% 2022:2026, .(f=round(mean(fail),3)), by=.(boro,yr)], boro~yr, value.var="f"))
print(H(R)[yr %in% c(2024,2026), .N, by=.(boro,yr)][, dcast(.SD, boro~yr, value.var="N")])
cat("leave-one-borough-out 2024->2026:\n")
for (b in unique(R$boro)) cat(b, fr(H(R)[yr==2024 & boro!=b]$fail), "->", fr(H(R)[yr==2026 & boro!=b]$fail), "\n")
f26 <- H(R)[yr==2026, .(u=sum(fail), n=.N), by=fac][order(-u)]
cat("2026H1: fails", sum(f26$u), "across", sum(f26$u>0), "facilities of", nrow(f26), "; top-10 facilities hold", sum(head(f26$u,10)), "\n")
f24 <- H(R)[yr==2024, .(u=sum(fail), n=.N), by=fac]
cat("2024H1: fails", sum(f24$u), "across", sum(f24$u>0), "facilities of", nrow(f24), "\n")
rep <- f26[u>=2, fac]
cat("drop facilities with >=2 fails in 2026H1 (", length(rep), "): 2024", fr(H(R)[yr==2024 & !fac %in% rep]$fail), "2026", fr(H(R)[yr==2026 & !fac %in% rep]$fail), "\n")
cat("share of facilities failing at least once, per-facility first H1 inspection only:\n")
print(H(R)[yr>=2022][order(date)][, .SD[1], by=.(fac,yr)][, .(n=.N, f=fr(fail)), by=yr][order(yr)])
