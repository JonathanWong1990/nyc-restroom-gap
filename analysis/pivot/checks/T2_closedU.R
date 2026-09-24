suppressMessages({library(data.table)}); options(scipen=999, width=200)
dd <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
ins <- fread(file.path(dd,"pipInspections_mp8v-wjtf_20260920.csv"), showProgress=FALSE)
mas <- fread(file.path(dd,"pipInspectionsMaster_yg3y-7juh_20260920.csv"), showProgress=FALSE)
rr <- fread(file.path(dd,"pipRestrooms_9byw-znpj_20260920.csv"))
setnames(ins,"inspectionid","inspection_id")
for (c in grep("^cs_",names(ins),value=TRUE)) ins[[c]] <- toupper(trimws(ins[[c]]))
mas[, date:=as.IDate(substr(date,1,10))][, yr:=year(date)][, doy:=yday(date)]
d <- merge(ins, mas[, .(inspection_id, prop_id, date, yr, doy, inspector, inspectiontype, comments, closed)], by="inspection_id")
subs <- c("cs_litter","cs_graffiti","cs_amenities","cs_structural")
d[, allN := cs_litter=="N"&cs_graffiti=="N"&cs_amenities=="N"&cs_structural=="N"]
d[, cls := fifelse(cs_overall_condition=="A","A", fifelse(cs_overall_condition=="U" & allN,"U_noSubs", fifelse(cs_overall_condition=="U","U_subs", "N")))]
cat("## class shares, H1 (doy<=179), all years\n")
t <- dcast(d[doy<=179, .N, by=.(yr,cls)], yr~cls, value.var="N", fill=0)
t[, rated:=A+U_noSubs+U_subs][, fail:=round((U_noSubs+U_subs)/rated,3)][, fail_noSubs:=round(U_noSubs/rated,3)][, fail_subs:=round(U_subs/rated,3)][, Nshare:=round(N/(rated+N),3)]
print(t)
set.seed(1)
cat("\n## sample comments, U with no subscores, 2025-26\n"); x <- d[cls=="U_noSubs" & yr>=2025 & comments!=""]; print(x[sample(.N, min(.N,25)), .(date, comments, closed)])
cat("\n## share of U_noSubs with non-empty comment by yr\n"); print(d[cls=="U_noSubs" & yr>=2018, .(n=.N, com=round(mean(comments!=""),2)), by=yr][order(yr)])
cat("\n## sample comments, N (unrated) 2026\n"); x <- d[cls=="N" & yr==2026 & comments!=""]; print(x[sample(.N, min(.N,15)), .(date, cs_litter, cs_amenities, comments)])
cat("\n## U_noSubs by month, 2022-2026\n"); print(dcast(d[yr>=2022, .(n=sum(cls=="U_noSubs")), by=.(yr,m=month(date))], m~yr, value.var="n"))
cat("\n## U_noSubs by current winterized flag in restroom register, H1\n")
rr[, wint := winterized=="Yes"]; w <- rr[, .(wint=any(wint), ltc=any(long_term_closure=="Yes")), by=prop_id]
d2 <- merge(d, w, by="prop_id", all.x=TRUE)
print(d2[doy<=179 & yr>=2022 & cls!="N", .(n=.N, failNoSubs=round(mean(cls=="U_noSubs"),3), failSubs=round(mean(cls=="U_subs"),3)), by=.(yr,wint)][order(wint,yr)])
cat("\n## ... by long-term closure flag (current)\n")
print(d2[doy<=179 & yr>=2022 & cls!="N", .(n=.N, failNoSubs=round(mean(cls=="U_noSubs"),3), failSubs=round(mean(cls=="U_subs"),3)), by=.(yr,ltc)][order(ltc,yr)])
cat("\n## earliest year in file\n"); print(range(d$yr))
