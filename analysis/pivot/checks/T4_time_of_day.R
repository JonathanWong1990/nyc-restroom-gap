# T4: could no-subscore U (restroom not accessible) be driven by earlier inspection times or day-of-week?
suppressMessages(library(data.table)); options(width=200)
dd <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/data_raw"
ins <- fread(file.path(dd,"pipInspections_mp8v-wjtf_20260920.csv")); mas <- fread(file.path(dd,"pipInspectionsMaster_yg3y-7juh_20260920.csv"))
setnames(ins,"inspectionid","inspection_id"); for (c in grep("^cs_",names(ins),value=TRUE)) ins[[c]] <- toupper(trimws(ins[[c]]))
mas[, date:=as.IDate(substr(date,1,10))][, yr:=year(date)][, doy:=yday(date)]
mas[, hr := as.integer(substr(begininspection,1,2))][, wd := wday(date)]
d <- merge(ins, mas[, .(inspection_id, yr, doy, hr, wd, closed)], by="inspection_id")[doy<=179 & yr>=2022 & cs_overall_condition %in% c("A","U")]
d[, noSub := cs_overall_condition=="U" & cs_litter=="N" & cs_graffiti=="N" & cs_amenities=="N" & cs_structural=="N"]
cat("begin-hour distribution by year (share of rated restroom inspections):\n")
print(dcast(d[, .N, by=.(yr, h=pmin(pmax(hr,7),14))][, s:=round(N/sum(N),3), by=yr], yr~h, value.var="s", fill=0))
cat("no-subscore U rate by begin hour, pooled 2022-25 vs 2026:\n")
print(dcast(d[, .(f=round(mean(noSub),3), n=.N), by=.(p=yr==2026, h=pmin(pmax(hr,7),14))], h~p, value.var=c("f","n")))
cat("weekend share by year:\n"); print(d[, .(wkend=round(mean(wd %in% c(1,7)),3)), by=yr][order(yr)])
cat("re-weight 2026 to 2022-25 hour mix -> expected noSub rate:\n")
w <- d[yr<2026, .N, by=.(h=pmin(pmax(hr,7),14))][, w:=N/sum(N)]
r <- d[yr==2026, .(f=mean(noSub)), by=.(h=pmin(pmax(hr,7),14))]
x <- merge(w, r, by="h"); cat(round(sum(x$w*x$f)/sum(x$w),3), " (raw 2026:", round(mean(d[yr==2026]$noSub),3), ")\n")
cat("closed field among noSub:\n"); print(d[noSub==TRUE, .N, by=.(yr, closed=closed!="")][order(yr)])
