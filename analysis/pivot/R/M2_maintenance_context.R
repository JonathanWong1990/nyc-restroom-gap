# Complaint extension and current spatial context for the maintenance pivot.
# Run after M1. Extensions are exploratory, not a new independent confirmation.
suppressPackageStartupMessages({library(data.table);library(sf);library(jsonlite)})
options(scipen=999); set.seed(6093)
rebuild <- Sys.getenv("RESTROOM_PROJ",unset="..")  # site layout: run from analysis/pivot/
dd <- file.path(rebuild,"data_raw"); out <- "outputs"  # run from Maintenance_Pivot_Feasibility/
o <- readRDS(file.path(out,"analysis_objects.rds"))
savecsv <- function(z,f) fwrite(z,file.path(out,f),na="")
st <- fread(file.path(dd,"parkstructures_n8q6-i44s_20260920.csv"))
st <- st[public_restroom==TRUE & !is.na(omppropid) & omppropid!=""]
# doitt_id is missing on 60 distinct buildings; Parks system is the unique key.
stopifnot(!anyNA(st$system),all(st$system!=""),!anyDuplicated(st$system))
center <- function(txt) {
  a <- suppressWarnings(as.numeric(unlist(fromJSON(txt,simplifyVector=FALSE))))
  if(length(a)<2 || length(a)%%2) return(c(NA_real_,NA_real_))
  a <- matrix(a,ncol=2,byrow=TRUE); colMeans(a)
}
cc <- t(vapply(st$multipolygon.coordinates,center,numeric(2)))
st[,`:=`(lon=cc[,1],lat=cc[,2])]
st <- st[is.finite(lon)&is.finite(lat)]
sp <- st_as_sf(st,coords=c("lon","lat"),crs=4326,remove=FALSE)
sp <- st_transform(sp,2263)
old <- st[!is.na(construction_year)&construction_year<=2019]
osp <- st_transform(st_as_sf(old,coords=c("lon","lat"),crs=4326,remove=FALSE),2263)
compl <- fread(file.path(dd,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
compl <- compl[complaint_type=="Urinating in Public" &
 location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station") &
 is.finite(latitude)&is.finite(longitude)]
compl[,date:=as.IDate(created_date)]
compl[,addr:=toupper(trimws(incident_address))]
compl[is.na(addr)|addr=="",addr:=paste(round(latitude,5),round(longitude,5))]
compl[,mon:=format(date,"%Y-%m")]
setorder(compl,date,unique_key)
compl <- unique(compl,by=c("addr","mon")); compl[,event_id:=.I]
cp <- st_transform(st_as_sf(compl,coords=c("longitude","latitude"),crs=4326),2263)
near <- st_is_within_distance(osp,cp,dist=400/0.3048)
links <- rbindlist(lapply(seq_along(near),function(i){
 if(!length(near[[i]])) return(NULL)
 data.table(prop_id=old$omppropid[i],event_id=compl$event_id[near[[i]]],date=compl$date[near[[i]]])
}))
links <- unique(links,by=c("prop_id","event_id"))
# Exact inspection-site ID join only; no guessed parent-park assignment.
panel <- copy(o$rated)[year>=2021 & prop_id %in% old$omppropid]
panel[,complaints_prior_year:=vapply(seq_len(.N),function(i)
 nrow(links[prop_id==panel$prop_id[i] & date<panel$asof[i] & date>=panel$asof[i]-365]),integer(1))]
panel[,log_complaints:=log1p(complaints_prior_year)]
f0 <- y ~ last_fail + recent_rate + log_days + borough + half
f1 <- update(f0,.~.+log_complaints)
train <- panel[year<=2024]; te <- panel[year>=2025]
m0 <- glm(f0,data=train,family=binomial()); m1 <- glm(f1,data=train,family=binomial())
te[,`:=`(history_only=as.numeric(predict(m0,te,type="response")),
 history_plus_complaints=as.numeric(predict(m1,te,type="response")),
 complaints_only=complaints_prior_year)]
topw <- function(s,k) {cut<-sort(s,decreasing=TRUE)[k];w<-as.numeric(s>cut);w[s==cut]<-(k-sum(w))/sum(s==cut);w}
auc <- function(y,p) {(sum(rank(p)[y==1])-sum(y)*(sum(y)+1)/2)/(sum(y)*sum(y==0))}
res <- rbindlist(lapply(c("history_only","history_plus_complaints","complaints_only"),function(nm)
 te[,{
 k<-ceiling(.N*.2);hits<-sum(topw(get(nm),k)*y)
 list(n=.N,failures=sum(y),k=k,hits=hits,precision=hits/k,recall=hits/sum(y),auc=auc(y,get(nm)))
 },by=period][,model:=nm]))
savecsv(res,"complaint_extension_metrics.csv")
savecsv(te,"complaint_extension_predictions.csv")
savecsv(panel[,.(rows=.N,positive_complaint_history=sum(complaints_prior_year>0),
 median=as.numeric(median(complaints_prior_year)),max=max(complaints_prior_year)),by=year],
 "complaint_extension_coverage.csv")
cat("\nCOMPLAINT EXTENSION (400m, preceding 365 days, matched property IDs):\n"); print(res)
cat("Complaint coefficient (descriptive, not causal):\n"); print(summary(m1)$coefficients["log_complaints",,drop=FALSE])

# Spatial context, intentionally separate from historical prediction.
# Only properties with exactly one geocoded restroom structure, and an unambiguous
# one-to-one match to the 2025 public register within 75m. All uncertain cases flagged.
reg <- fread(file.path(dd,"nycrestrooms_i7jb-7jku_20260920.csv"))
reg <- reg[is.finite(latitude)&is.finite(longitude)]; reg[,register_id:=.I]
rp <- st_transform(st_as_sf(reg,coords=c("longitude","latitude"),crs=4326,remove=FALSE),2263)
counts <- st[,.(n_structures=.N),by=omppropid]
single <- st[omppropid %in% counts[n_structures==1,omppropid]]
ssp <- st_transform(st_as_sf(single,coords=c("lon","lat"),crs=4326,remove=FALSE),2263)
matched <- st_is_within_distance(ssp,rp,dist=75/0.3048)
map <- data.table(prop_id=single$omppropid,lon=single$lon,lat=single$lat,
 register_matches=lengths(matched),register_id=vapply(matched,function(ii)if(length(ii)==1)ii else NA_integer_,integer(1)))
duplicated_register <- map[!is.na(register_id),.N,by=register_id][N>1,register_id]
map[register_id %in% duplicated_register,register_id:=NA_integer_]
map[,`:=`(register_name=NA_character_,listed_status=NA_character_,
 nearest_alternative_m=NA_real_,alternatives_within400m=NA_integer_)]
op <- which(reg$status=="Operational")
for(i in which(!is.na(map$register_id))){
 ri<-map$register_id[i];others<-setdiff(op,ri)
 dist<-as.numeric(st_distance(ssp[i,],rp[others,]))*.3048
 map[i,`:=`(register_name=reg$facility_name[ri],listed_status=reg$status[ri],
 nearest_alternative_m=min(dist),alternatives_within400m=sum(dist<=400))]
}
future <- merge(o$future,map,by="prop_id",all.x=TRUE)
setorder(future,priority_order)
savecsv(future,"priority_list_with_spatial_context.csv")
savecsv(map,"structure_register_crosswalk.csv")
spatial <- future[,.(eligible=.N,single_structure=sum(!is.na(register_matches)),
 unambiguous_register=sum(!is.na(register_id)),
 listed_operational=sum(listed_status=="Operational",na.rm=TRUE),
 no_listed_alternative400=sum(alternatives_within400m==0,na.rm=TRUE))]
cat("\nSPATIAL MATCH AUDIT:\n");print(spatial)
cat("\nTOP 20 WITH SPATIAL CONTEXT (snapshot, not an engineering work order):\n")
print(future[1:20,.(priority_order,prop_id,site_name,risk_score,last_fail,register_name,
 listed_status,nearest_alternative_m,alternatives_within400m)])
jsonlite::write_json(list(complaint_extension_rows=nrow(panel),train=nrow(train),test=nrow(te),
 spatial=spatial,notes=c("Exploratory extension, same held-out periods as M1",
 "Geometry is the cached current footprint, restricted to known pre-2020 structures for complaint tests",
 "400m straight-line proximity is not walking access; posted hours and closures are not verified",
 "Do not equate no listed alternative with no actual alternative or quantify loss of population coverage")),
 file.path(out,"context_summary.json"),pretty=TRUE,auto_unbox=TRUE)
