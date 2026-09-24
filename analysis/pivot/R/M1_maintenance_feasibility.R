# M1: frozen-time maintenance-priority backtest. Run from Restroom_Rebuild:
# Rscript R/M1_maintenance_feasibility.R
# See Maintenance_Pivot_Feasibility/notes/maintenance_pivot_protocol.md for pre-performance design.
suppressPackageStartupMessages({library(data.table); library(rpart); library(ggplot2)})
options(scipen=999); set.seed(6093)
rebuild <- Sys.getenv("RESTROOM_PROJ", unset="..")  # site layout: run from analysis/pivot/
dd <- file.path(rebuild,"data_raw"); out <- "outputs"  # run from Maintenance_Pivot_Feasibility/
dir.create(out, recursive=TRUE, showWarnings=FALSE)
read <- function(f) fread(file.path(dd,f), showProgress=FALSE)
savecsv <- function(d,f) fwrite(d,file.path(out,f),na="")
x <- read("pipInspections_mp8v-wjtf_20260920.csv")
m <- read("pipInspectionsMaster_yg3y-7juh_20260920.csv")
s <- read("pipAllSites_buk3-3qpr_20260920.csv")
stopifnot(!anyDuplicated(m$inspection_id),!anyDuplicated(s$prop_id))
stopifnot(!anyDuplicated(x[,.(inspectionid,csnumber)]))
for (cn in grep("^cs_",names(x),value=TRUE)) set(x,j=cn,value=toupper(trimws(x[[cn]])))
d <- merge(x,m[,.(inspection_id,prop_id,date,inspaddeddate,inspectiontype)],
           by.x="inspectionid",by.y="inspection_id",all.x=TRUE)
stopifnot(nrow(d)==nrow(x),!anyNA(d$prop_id))
d[,date:=as.IDate(date)]
d[,available_date:=pmax(date,as.IDate(inspaddeddate),na.rm=TRUE)]
audit <- list(raw_rows=nrow(x),raw_visits=uniqueN(x$inspectionid),
              raw_properties=uniqueN(d$prop_id),last_date=as.character(max(d$date)))
state <- function(z) if(any(z=="U")) "U" else if(all(z=="A")) "A" else "N"
# Aggregate room/comfort-station rows, including multiple records on same site/day.
v <- d[inspectiontype=="PIP",.(status=state(cs_overall_condition),
     structural=state(cs_structural),amenities=state(cs_amenities),
     litter=state(cs_litter),graffiti=state(cs_graffiti),
     available_date=max(available_date),n_rooms=.N),by=.(prop_id,date)]
setorder(v,prop_id,date)
v[,y:=fifelse(status=="U",1L,fifelse(status=="A",0L,NA_integer_))]
v[,borough:=substr(prop_id,1,1)]
v <- merge(v,s[,.(prop_id,parent=propnum,site_name,prop_name)],by="prop_id",all.x=TRUE)
v[is.na(parent)|parent=="",parent:=sub("-.*$","",prop_id)]
setorder(v,prop_id,date)
savecsv(v,"regular_pip_site_visits.csv")

features <- function(h,cut) {
  h <- h[date < cut & available_date < cut]
  if(!nrow(h)) return(NULL)
  last <- h[.N]
  if(as.integer(cut-last$date)>730) return(NULL)
  r <- h[date>=cut-1095]
  rated <- r[!is.na(y)]
  if(!nrow(rated)) return(NULL)
  rr <- tail(rated,3)
  data.table(prop_id=last$prop_id,parent=last$parent,site_name=last$site_name,
    borough=last$borough,asof=cut,half=ifelse(month(cut)==1,"H1","H2"),
    last_date=last$date,max_available=max(h$available_date),
    days_since=as.integer(cut-last$date),n_history=nrow(r),n_rated=nrow(rated),
    last_status=last$status,last_fail=tail(rated$y,1),
    last_struct=as.integer(last$structural=="U"),
    last_amenity=as.integer(last$amenities=="U"),
    last_litter=as.integer(last$litter=="U"),
    recent_rate=mean(rr$y),history_rate=(sum(rated$y)+.5)/(nrow(rated)+5),
    unknown_rate=mean(is.na(r$y)),last_n=as.integer(last$status=="N"))
}
periods <- as.IDate(sprintf("%d-%s",rep(2018:2026,each=2),rep(c("01-01","07-01"),9)))
periods <- periods[periods<=as.IDate("2026-01-01")]
by_site <- split(v,by="prop_id",keep.by=TRUE)
rows <- lapply(periods,function(cut){
  cut <- as.IDate(cut,origin="1970-01-01")
  end <- if(month(cut)==1) as.IDate(sprintf("%d-07-01",year(cut))) else as.IDate(sprintf("%d-01-01",year(cut)+1))
  rbindlist(lapply(by_site,function(h){
    z <- features(h,cut); if(is.null(z)) return(NULL)
    f <- h[date>=cut & date<end][1]
    z[,`:=`(followup_date=f$date,target_available=f$available_date,target_status=f$status,y=f$y)]
    z
  }),fill=TRUE)
})
p <- rbindlist(rows)
p[,`:=`(year=year(asof),period=paste0(year(asof),half),
         log_days=log1p(days_since),log_history=log1p(n_history))]
stopifnot(all(p$last_date<p$asof),all(p$max_available<p$asof),
          !anyDuplicated(p[,.(prop_id,asof)]),
          all(p[!is.na(followup_date),followup_date>=asof]))
savecsv(p,"planning_cohort_all.csv")
coverage <- p[,.(eligible=.N,followed=sum(!is.na(followup_date)),
  rated=sum(!is.na(y)),unknown=sum(!is.na(followup_date)&is.na(y)),
  failed=sum(y,na.rm=TRUE)),by=.(year,period)]
savecsv(coverage,"cohort_coverage.csv")
print(coverage)
q <- p[!is.na(y)]
q[,borough:=factor(borough,levels=c("B","M","Q","R","X"))]
q[,half:=factor(half,levels=c("H1","H2"))]
dev <- q[year<=2023]; val <- q[year==2024]; test <- q[year>=2025]
stopifnot(all(dev$target_available < as.IDate("2024-01-01")),
          all(val$target_available < as.IDate("2025-01-01")))

auc <- function(y,p) {
  n1 <- sum(y==1); n0 <- sum(y==0)
  if(n1*n0==0) return(NA_real_)
  (sum(rank(p,ties.method="average")[y==1])-n1*(n1+1)/2)/(n1*n0)
}
topw <- function(score,k) {
  k <- min(length(score),k); boundary <- sort(score,decreasing=TRUE)[k]
  w <- as.numeric(score>boundary)
  w[score==boundary] <- (k-sum(w))/sum(score==boundary)
  w
}
metric <- function(y,score,k) {
  w <- topw(score,k); hits <- sum(w*y)
  list(n=length(y),failures=sum(y),k=sum(w),hits=hits,precision=hits/sum(w),
       recall=hits/sum(y),random_hits=sum(w)*mean(y),lift=hits/sum(w)/mean(y),
       auc=auc(y,score),brier=mean((y-score)^2),mean_score=mean(score),rate=mean(y))
}
evaluate <- function(z,cols) rbindlist(lapply(cols,function(cn){
  rbindlist(lapply(c(.1,.2,.3,50),function(b){
    z[,as.data.table(metric(y,get(cn),if(b<1)max(1,ceiling(.N*b)) else min(.N,b))),by=period][,
      `:=`(model=cn,budget=ifelse(b<1,paste0(b*100,"pct"),"50"))]
  }))
}))
add_rules <- function(z,base_rate) {
  z <- copy(z)
  z[,`:=`(random=base_rate,last_rating=last_fail,last_three=recent_rate,
           smoothed_history=history_rate,last_then_history=(last_fail+.1*recent_rate)/1.1)]
  z
}
basic <- y ~ last_fail + recent_rate + log_days + borough + half
full <- y ~ last_fail + recent_rate + history_rate + last_struct + last_amenity +
  last_litter + last_n + unknown_rate + log_days + log_history + borough + half
fits <- list(logistic_basic=glm(basic,data=dev,family=binomial()),
             logistic_history=glm(full,data=dev,family=binomial()))
for(cp in c(.005,.01,.02,.04)) {
  fits[[paste0("tree_",cp)]] <- rpart(full,data=dev,method="class",
    control=rpart.control(cp=cp,maxdepth=3,minsplit=60,minbucket=25,xval=0))
}
pred <- function(fit,z) if(inherits(fit,"rpart")) predict(fit,newdata=z,type="prob")[,"1"] else
  as.numeric(predict(fit,newdata=z,type="response"))
val <- add_rules(val,mean(dev$y))
for(nm in names(fits)) val[,(nm):=pred(fits[[nm]],val)]
rules <- c("random","last_rating","last_three","smoothed_history","last_then_history")
vm <- evaluate(val,c(rules,names(fits))); savecsv(vm,"validation_metrics.csv")
selection <- vm[budget=="20pct",.(precision=mean(precision),brier=mean(brier)),by=model]
setorder(selection,-precision,brier)
chosen <- selection[model %in% names(fits),model][1]
baseline <- selection[model %in% setdiff(rules,"random"),model][1]
cat("\n2024 selection (frozen before test):\n"); print(selection)
cat("Chosen model:",chosen,"; benchmark:",baseline,"\n")
savecsv(selection,"validation_selection.csv")
train <- q[year<=2024]
finals <- list(logistic_basic=glm(basic,data=train,family=binomial()),
               logistic_history=glm(full,data=train,family=binomial()))
for(cp in c(.005,.01,.02,.04)) finals[[paste0("tree_",cp)]] <- rpart(full,data=train,method="class",
  control=rpart.control(cp=cp,maxdepth=3,minsplit=60,minbucket=25,xval=0))
test <- add_rules(test,mean(train$y))
for(nm in names(finals)) test[,(nm):=pred(finals[[nm]],test)]
tm <- evaluate(test,c(rules,names(finals))); savecsv(tm,"test_metrics.csv")
savecsv(test,"test_predictions.csv")
cat("\nHELD-OUT 20% RESULTS:\n")
print(tm[budget=="20pct" & model %in% c("random",baseline,chosen),
 .(period,model,n,failures,k,hits,precision,recall,lift,auc,brier)])

# Paired parent-park bootstrap, re-ranking within each resampled period.
# Parent rather than row resampling preserves repeated site observations and
# dependence between inspection zones in the same park. Fixed fitted models.
set.seed(6093)
parents <- unique(test$parent)
test_by_parent <- split(test,by="parent",keep.by=TRUE)
boot <- rbindlist(lapply(seq_len(1000),function(b){
  sampled <- sample(parents,length(parents),replace=TRUE)
  z <- rbindlist(test_by_parent[sampled])
  vals <- z[,{
    k <- ceiling(.N*.2); a <- sum(topw(get(chosen),k)*y)/k
    bb <- sum(topw(get(baseline),k)*y)/k
    list(model_precision=a,baseline_precision=bb,random_precision=mean(y),
         auc_model=auc(y,get(chosen)))
  },by=period]
  data.table(draw=b,delta_vs_rule=mean(vals$model_precision-vals$baseline_precision),
     delta_vs_random=mean(vals$model_precision-vals$random_precision),
     model_precision=mean(vals$model_precision),baseline_precision=mean(vals$baseline_precision),
     auc=mean(vals$auc_model))
}))
ci <- melt(boot,id.vars="draw")[,.(mean=mean(value),lower=quantile(value,.025),
 upper=quantile(value,.975)),by=variable]
savecsv(ci,"bootstrap_ci.csv"); cat("\nPARENT-PARK BOOTSTRAP:\n"); print(ci)

# Previously passing cohort distinguishes predicting a new failure from simply
# rediscovering a previously recorded problem. No retraining or reselection.
passing <- test[last_fail==0]
pm <- evaluate(passing,c("random",baseline,chosen))
savecsv(pm,"previously_passing_metrics.csv")
groups <- test[,.(n=.N,failures=sum(y),rate=mean(y),
 mean_score=mean(get(chosen)),auc=auc(y,get(chosen))),by=.(period,borough)]
savecsv(groups,"borough_metrics.csv")
test[,risk_bin:=cut(get(chosen),breaks=c(0,.05,.1,.2,.3,.5,1),include.lowest=TRUE)]
cal <- test[,.(n=.N,predicted=mean(get(chosen)),observed=mean(y)),by=.(period,risk_bin)]
savecsv(cal,"calibration.csv")
transitions <- test[,.(n=.N,failures=sum(y),rate=mean(y)),by=.(period,last_fail)]
savecsv(transitions,"last_rating_transitions.csv")

# Outcome observation check on ALL eligible sites, scored with frozen model.
alltest <- copy(p[year>=2025]); alltest[,borough:=factor(borough,levels=levels(train$borough))]
alltest[,half:=factor(half,levels=levels(train$half))]
alltest[,score:=pred(finals[[chosen]],alltest)]
alltest <- add_rules(alltest,mean(train$y))
alltest[,(chosen):=score]
alltest[,outcome_group:=fifelse(is.na(followup_date),"No follow-up",
 fifelse(is.na(y),"Unrated first visit","Rated first visit"))]
obs <- alltest[,.(n=.N,mean_risk=mean(score),last_fail_rate=mean(last_fail)),by=.(period,outcome_group)]
savecsv(obs,"observation_bias.csv")
savecsv(alltest,"all_eligible_test_predictions.csv")

# Descriptive condition trend, consistent with site-level aggregation.
trend <- v[year(date)>=2018,.(visits=.N,rated=sum(!is.na(y)),
 failures=sum(y,na.rm=TRUE),unknown=sum(is.na(y))),by=.(year=year(date),half=ifelse(month(date)<=6,"H1","H2"))]
trend[,rate:=failures/rated]; savecsv(trend,"site_condition_trend.csv")
co <- as.data.table(summary(finals$logistic_history)$coefficients,keep.rownames="term")
setnames(co,c("term","estimate","se","z","p"))
co[,`:=`(odds_ratio=exp(estimate),lower=exp(estimate-1.96*se),upper=exp(estimate+1.96*se))]
savecsv(co,"logistic_coefficients_descriptive.csv")
# Model-based coefficient intervals are descriptive, not cluster-corrected claims.

plotd <- tm[budget=="20pct" & model %in% c("random",baseline,chosen)]
plotd[,label:=factor(model,levels=c("random",baseline,chosen),
 labels=c("Random allocation","Last-three inspection rule","Logistic regression")) ]
g <- ggplot(plotd,aes(period,precision,fill=label))+geom_col(position="dodge",width=.7)+
 scale_y_continuous(labels=function(x)paste0(round(100*x),"%"),limits=c(0,1))+
 scale_fill_manual(values=c("#acb7c0","#4286a5","#de8f35"))+
 labs(title="Which priority list finds more unacceptable conditions?",
 subtitle="Held-out first-visit outcomes with A/U ratings; capacity = 20% of rated sites",
 x=NULL,y="Unacceptable among prioritised sites",fill=NULL,
 caption="Choices selected on 2024, refitted through 2024. Ties receive fractional allocation.\nUnknown/unobserved outcomes excluded; this measures detection, not failures prevented.")+
 theme_minimal(base_size=12)+theme(legend.position="bottom",plot.caption=element_text(hjust=0))
ggsave(file.path(out,"heldout_priority_comparison.png"),g,width=10,height=6,dpi=160)

# Prospective planning snapshot as of 1 July 2026: no outcomes claimed.
future <- rbindlist(lapply(by_site,features,cut=as.IDate("2026-07-01")),fill=TRUE)
future[,`:=`(log_days=log1p(days_since),log_history=log1p(n_history))]
future[,borough:=factor(borough,levels=levels(train$borough))]
future[,half:=factor(half,levels=levels(train$half))]
future[,risk_score:=pred(finals[[chosen]],future)]
future[,(baseline):=switch(baseline,last_rating=last_fail,last_three=recent_rate,
 smoothed_history=history_rate,last_then_history=(last_fail+.1*recent_rate)/1.1)]
setorder(future,-risk_score,prop_id)
future[,priority_order:=.I]
savecsv(future,"illustrative_july2026_priority_list.csv")

summary <- list(protocol="Maintenance_Pivot_Feasibility/notes/maintenance_pivot_protocol.md",raw=audit,
 unit="Inspection property / half-year, aggregated comfort-station outcomes",
 development=list(n=nrow(dev),failures=sum(dev$y)),
 validation=list(n=nrow(val),failures=sum(val$y)),
 test=list(n=nrow(test),failures=sum(test$y),sites=uniqueN(test$prop_id),parents=uniqueN(test$parent)),
 chosen_model=chosen,chosen_baseline=baseline,
 test_20pct=tm[budget=="20pct" & model %in% c("random",baseline,chosen)],
 confidence_intervals=ci,coverage=coverage,
 limits=c("Outcome only observed at first follow-up inspection; unknown and unvisited sites excluded from performance",
 "2026 data end 28 June; not 30 June", "Performance is detection under historical practice, not treatment effectiveness",
 "Probability calibration may drift; current ranking is an illustrative July snapshot, not current verified condition"))
jsonlite::write_json(summary,file.path(out,"summary.json"),pretty=TRUE,auto_unbox=TRUE,na="null")
saveRDS(list(visits=v,panel=p,rated=q,train=train,val=val,test=test,
 models=finals,chosen=chosen,baseline=baseline,future=future),file.path(out,"analysis_objects.rds"))
writeLines(capture.output(sessionInfo()),file.path(out,"session_info.txt"))
cat("\nDONE. Output:",normalizePath(out),"\n")
