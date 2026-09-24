# Verification and deployment-denominator checks. No model re-selection.
suppressPackageStartupMessages(library(data.table))
options(scipen=999);set.seed(6093)
rebuild<-Sys.getenv("RESTROOM_PROJ",unset="..")  # site layout: run from analysis/pivot/
out<-"outputs"  # run from Maintenance_Pivot_Feasibility/
o<-readRDS(file.path(out,"analysis_objects.rds"))
all<-fread(file.path(out,"all_eligible_test_predictions.csv"))
savecsv<-function(z,f)fwrite(z,file.path(out,f),na="")
topw<-function(s,k){cut<-sort(s,decreasing=TRUE)[k];w<-as.numeric(s>cut);w[s==cut]<-(k-sum(w))/sum(s==cut);w}
deploy<-function(z,methods,budgets=c(.1,.2,.3,50))rbindlist(lapply(methods,function(nm)
 rbindlist(lapply(budgets,function(b)z[,{
  k<-if(b<1)ceiling(.N*b) else min(b,.N)
  w<-topw(get(nm),k);known<-!is.na(y);hits<-sum(w*y,na.rm=TRUE)
  rated_slots<-sum(w*known);unrated_slots<-sum(w*(outcome_group=="Unrated first visit"))
  missing_slots<-sum(w*(outcome_group=="No follow-up"))
  list(eligible=.N,k=k,known_failures=hits,rated_slots=rated_slots,
   unrated_slots=unrated_slots,no_followup_slots=missing_slots,
   precision_among_rated=hits/rated_slots,precision_lower=hits/k,
   precision_upper=(hits+k-rated_slots)/k,recall_observed=hits/sum(y,na.rm=TRUE))
 },by=period][,`:=`(model=nm,budget=ifelse(b<1,paste0(b*100,"pct"),"50"))]))))
dr<-deploy(all,c("random",o$baseline,"smoothed_history",o$chosen))
savecsv(dr,"all_eligible_selection_metrics.csv")
cat("\nACTUAL PLANNING DENOMINATOR, TOP 20% OF ALL ELIGIBLE:\n")
print(dr[budget=="20pct"])

# Unconditional known-failure yield: unknowns receive no invented outcome. This is
# a lower bound, not total failure prevalence. Cluster intervals are descriptive.
byparent<-split(all,by="parent",keep.by=TRUE); ids<-names(byparent)
bt<-rbindlist(lapply(seq_len(1000),function(b){
 z<-rbindlist(byparent[sample(ids,length(ids),replace=TRUE)])
 r<-deploy(z,c("random",o$baseline,"smoothed_history",o$chosen),budgets=.2)
 w<-dcast(r,period~model,value.var="precision_lower")
 data.table(draw=b,known_yield_delta_rule=mean(w[[o$chosen]]-w[[o$baseline]]),
 known_yield_delta_random=mean(w[[o$chosen]]-w$random),
 known_yield_delta_history=mean(w[[o$chosen]]-w$smoothed_history))
}))
ci<-melt(bt,id.vars="draw")[,.(mean=mean(value),lower=quantile(value,.025),upper=quantile(value,.975)),by=variable]
savecsv(ci,"all_eligible_bootstrap_ci.csv");print(ci)

# Concentration: does the result disappear without the five largest park clusters?
big<-o$test[,.N,by=parent][order(-N)][1:5,parent]
t<-o$test[!parent %in% big]
conc<-rbindlist(lapply(c("random",o$baseline,o$chosen),function(nm)t[,{
 k<-ceiling(.N*.2);hits<-sum(topw(get(nm),k)*y)
 list(n=.N,k=k,hits=hits,precision=hits/k,recall=hits/sum(y))
},by=period][,model:=nm]))
savecsv(conc,"excluding_five_largest_parks.csv")
savecsv(o$test[,.N,by=parent][order(-N)][1:10],"largest_parent_clusters.csv")

# Calibrated probability is a different claim from useful ranking.
cal<-o$test[,.(n=.N,failures=sum(y),observed_rate=mean(y),
 predicted_rate=mean(get(o$chosen))),by=period]
savecsv(cal,"period_calibration.csv")
# Selected model coefficient table with parent-park clustered standard errors.
fit<-o$models[[o$chosen]]
if(inherits(fit,"glm")){
 vc<-sandwich::vcovCL(fit,cluster=o$train$parent)
 cf<-data.table(term=names(coef(fit)),estimate=as.numeric(coef(fit)),se=sqrt(diag(vc)))
 cf[,`:=`(odds_ratio=exp(estimate),lower=exp(estimate-1.96*se),upper=exp(estimate+1.96*se))]
 savecsv(cf,"selected_model_clustered_coefficients.csv")
}
tm<-fread(file.path(out,"test_metrics.csv"))
ag<-tm[budget=="20pct" & model %in% c("random",o$baseline,"smoothed_history",o$chosen),
 .(n=sum(n),failures=sum(failures),slots=sum(k),hits=sum(hits),
 precision=sum(hits)/sum(k),recall=sum(hits)/sum(failures)),by=model]
savecsv(ag,"pooled_heldout_results.csv");cat("\nPOOLED RATED-COHORT RESULT:\n");print(ag)

# Main communication figure shows every relevant simple comparator, including the
# three-year rule that was weaker on validation but equally good on held-out data.
plotd<-copy(ag)
plotd[,label:=factor(model,levels=c("random","last_three","smoothed_history","logistic_basic"),
 labels=c("Random\nallocation","Last 3\ninspections","Three-year\nhistory rule","Logistic\nregression"))]
g<-ggplot2::ggplot(plotd,ggplot2::aes(label,hits,fill=label))+
 ggplot2::geom_col(width=.65)+
 ggplot2::geom_text(ggplot2::aes(label=sprintf("%.1f",hits)),vjust=-.5,size=4.5)+
 ggplot2::scale_fill_manual(values=c("#aeb8c1","#4286a5","#2c6975","#de8f35"))+
 ggplot2::scale_y_continuous(limits=c(0,110),expand=ggplot2::expansion(mult=c(0,.02)))+
 ggplot2::labs(title="Inspection history helps. A complex model adds little.",
 subtitle="2025-2026 holdout: prioritise 20% of sites within each rated cohort",
 x=NULL,y="Observed unacceptable outcomes captured (244 total)",
 caption="338 total priority slots across three half-years; repeated sites can appear in different periods.\nTied rules/random selection show expected counts. Unknown and unvisited outcomes are excluded.\nThis measures prioritisation of observed conditions, not failures prevented.")+
 ggplot2::theme_minimal(base_size=12)+
 ggplot2::theme(legend.position="none",plot.caption=ggplot2::element_text(hjust=0))
ggplot2::ggsave(file.path(out,"main_comparison_all_rules.png"),g,width=10,height=6,dpi=160)

dg<-dr[budget=="20pct",.(slots=sum(k),known_failures=sum(known_failures),
 unknown_slots=sum(unrated_slots+no_followup_slots)),by=model]
savecsv(dg,"pooled_all_eligible_results.csv")
dg[,label:=factor(model,levels=c("random","last_three","smoothed_history","logistic_basic"),
 labels=c("Random\nallocation","Last 3\ninspections","Three-year\nhistory rule","Logistic\nregression"))]
g2<-ggplot2::ggplot(dg,ggplot2::aes(label,known_failures,fill=label))+
 ggplot2::geom_col(width=.65)+
 ggplot2::geom_text(ggplot2::aes(label=sprintf("%.1f",known_failures)),vjust=-.5,size=4.5)+
 ggplot2::scale_fill_manual(values=c("#aeb8c1","#4286a5","#2c6975","#de8f35"))+
 ggplot2::scale_y_continuous(limits=c(0,105),expand=ggplot2::expansion(mult=c(0,.02)))+
 ggplot2::labs(title="Prior inspection history identifies more recorded problems",
 subtitle="Select 20% of ALL eligible sites before observing their later inspection results",
 x=NULL,y="Subsequently recorded unacceptable outcomes in the priority list",
 caption="411 slots across three half-years (2025 H1, 2025 H2, 2026 H1); 244 observed failures in the full cohort.\nOutcomes remain unknown for 99 model-selected slots; no pass/fail outcome has been invented.\nRandom allocation and tied rules show expected counts. These are not failures prevented.")+
 ggplot2::theme_minimal(base_size=12)+
 ggplot2::theme(legend.position="none",plot.caption=ggplot2::element_text(hjust=0))
ggplot2::ggsave(file.path(out,"all_eligible_priority_comparison.png"),g2,width=10,height=6,dpi=160)

# Audit final joins/time boundaries and important finite-prediction properties.
stopifnot(!anyDuplicated(o$panel[,.(prop_id,asof)]),
 all(o$panel$last_date<o$panel$asof),all(o$panel$max_available<o$panel$asof),
 all(o$train$target_available<as.IDate("2025-01-01")),
 !anyNA(o$test[[o$chosen]]),all(o$test[[o$chosen]]>=0 & o$test[[o$chosen]]<=1),
 all(abs(tm$hits/tm$k-tm$precision)<1e-10),
 all(abs(dr$rated_slots+dr$unrated_slots+dr$no_followup_slots-dr$k)<1e-8))
cat("\nQA PASS: unique units; date and record-availability cutoffs; finite predictions; metric arithmetic; missingness accounting.\n")
writeLines(c("QA PASS",paste("Selected model:",o$chosen),paste("Selected baseline:",o$baseline),
 "No outcome-based model reselection during verification.",
 "Both rated-cohort and all-eligible selection denominators reported."),file.path(out,"verification.txt"))
inputs<-file.path(rebuild,"data_raw",c("pipInspections_mp8v-wjtf_20260920.csv",
 "pipInspectionsMaster_yg3y-7juh_20260920.csv","pipAllSites_buk3-3qpr_20260920.csv",
 "parkstructures_n8q6-i44s_20260920.csv","nycrestrooms_i7jb-7jku_20260920.csv",
 "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
savecsv(data.table(file=basename(inputs),md5=unname(tools::md5sum(inputs))),"input_manifest.csv")
