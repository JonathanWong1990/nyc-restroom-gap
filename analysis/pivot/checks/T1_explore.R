# T1_explore.R - adversarial stress test of the A8 restroom-failure trend (exploratory pass)
suppressMessages({library(data.table)}); options(scipen=999, width=200)
dd <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
ins <- fread(file.path(dd,"pipInspections_mp8v-wjtf_20260920.csv"), showProgress=FALSE)
mas <- fread(file.path(dd,"pipInspectionsMaster_yg3y-7juh_20260920.csv"), showProgress=FALSE)
setnames(ins,"inspectionid","inspection_id")
for (c in grep("^cs_",names(ins),value=TRUE)) ins[[c]] <- toupper(trimws(ins[[c]]))
mas[, date:=as.IDate(substr(date,1,10))][, yr:=year(date)][, doy:=yday(date)]
mas[, added:=as.IDate(substr(inspaddeddate,1,10))][, lag:=as.integer(added-date)]
d <- merge(ins, mas[, .(inspection_id, prop_id, date, yr, doy, inspector, inspectiontype, season, round, overall_condition, closed, lag, added)], by="inspection_id")
d[, boro:=substr(prop_id,1,1)][, h1:=doy<=179]
cat("rows", nrow(d), "unmatched", nrow(ins)-nrow(d), "\n")
cat("\n## U/S coding by year (overall + subscores), all rows, H1\n")
for (c in c("cs_overall_condition","cs_litter","cs_graffiti","cs_amenities","cs_structural")) {
 t <- dcast(d[yr>=2018 & h1, .N, by=.(yr,v=get(c))], yr~v, value.var="N", fill=0); cat(c,"\n"); print(t)}
cat("\n## overall vs structural consistency by year (H1): P(overall U | struct U), P(overall U | struct U/S), P(overall U| all subs A)\n")
print(d[yr>=2018 & h1, .(n_sU=sum(cs_structural=="U"), pU_sU=round(mean(cs_overall_condition[cs_structural=="U"]=="U"),3),
   n_sUS=sum(cs_structural=="U/S"), pU_sUS=round(mean(cs_overall_condition[cs_structural=="U/S"]=="U"),3),
   pU_allA=round(mean(cs_overall_condition[cs_litter=="A"&cs_graffiti=="A"&cs_amenities=="A"&cs_structural=="A"]=="U"),3),
   pU_overallN_subsA=sum(cs_overall_condition=="N")), by=yr][order(yr)])
cat("\n## number of subscores rated (A/U/U-S) among overall A/U, H1\n")
d[, nrated:= (cs_litter %in% c("A","U","U/S"))+(cs_graffiti %in% c("A","U","U/S"))+(cs_amenities %in% c("A","U","U/S"))+(cs_structural %in% c("A","U","U/S"))]
print(dcast(d[yr>=2018 & h1 & cs_overall_condition %in% c("A","U"), .N, by=.(yr,nrated)], yr~nrated, value.var="N", fill=0))
cat("\n## inspection type of restroom inspections, H1\n")
print(dcast(d[yr>=2018 & h1, .N, by=.(yr,inspectiontype)], yr~inspectiontype, value.var="N", fill=0))
cat("\n## fail rate by type H1\n")
print(dcast(d[yr>=2018 & h1 & cs_overall_condition %in% c("A","U"), .(f=round(mean(cs_overall_condition=="U"),3)), by=.(yr,inspectiontype)], yr~inspectiontype, value.var="f"))
cat("\n## entry lag (days) by year H1\n")
print(d[yr>=2018 & h1, .(med=as.numeric(median(lag,na.rm=T)), p90=as.numeric(quantile(lag,.9,na.rm=T)), gt7=round(mean(lag>7,na.rm=T),3), na=sum(is.na(lag))), by=yr][order(yr)])
cat("\n## month-by-month overall fail 2023-2026\n")
print(dcast(d[yr>=2022 & cs_overall_condition %in% c("A","U"), .(f=round(mean(cs_overall_condition=="U"),3)), by=.(yr,m=month(date))], m~yr, value.var="f"))
cat("\n## seasons/round in 2026\n"); print(d[yr>=2024, .N, by=.(yr,season,round)][order(yr,season,round)])
cat("\n## what makes overall U in 2026 vs 2024 (H1): subscore pattern among overall U\n")
print(d[yr %in% c(2024,2026) & h1 & cs_overall_condition=="U", .N, by=.(yr, pat=paste(cs_litter,cs_graffiti,cs_amenities,cs_structural))][order(yr,-N)][, head(.SD,8), by=yr])
