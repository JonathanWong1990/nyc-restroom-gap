# 93_winterization.R — causal test: do seasonal (winter-closed) restrooms show a winter
# rise in nearby public urination, relative to year-round facilities?
# Catchment narrowed to 250m around the FACILITY (not the tract) so park interior and
# surrounding street are not pooled. Alcohol summonses used as a placebo outcome.
suppressMessages({library(sf); library(dplyr); library(tidyr); library(MASS)})
options(scipen=999); D <- "data_raw"; R250 <- 250/0.3048

rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"), stringsAsFactors=FALSE)
rr$fid <- seq_len(nrow(rr))
rr <- rr |> filter(status=="Operational", !is.na(latitude), !is.na(longitude),
                   open %in% c("Year Round","Seasonal"))
cat("operational facilities:", nrow(rr), " seasonal:", sum(rr$open=="Seasonal"),
    " year-round:", sum(rr$open=="Year Round"), "\n")
fsf <- st_as_sf(rr, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)
buf <- st_buffer(fsf |> dplyr::select(fid, open), R250)

# park acreage within the same catchment — the confound that killed the tract-level version
pk <- readRDS(file.path(D,"parksprops_sf_20260920.rds")) |> st_transform(2263) |> st_make_valid()
pint <- suppressWarnings(st_intersection(buf |> dplyr::select(fid), pk |> dplyr::select(geometry)))
pint$a <- as.numeric(st_area(pint))/43560
pac <- pint |> st_drop_geometry() |> group_by(fid) |> summarise(park_ac=sum(a), .groups="drop")

load_pts <- function(f){
  x <- read.csv(file.path(D,f), stringsAsFactors=FALSE)
  x$lat <- suppressWarnings(as.numeric(x$latitude)); x$lon <- suppressWarnings(as.numeric(x$longitude))
  x |> filter(!is.na(lat), !is.na(lon)) |> mutate(ym=substr(occur_date,1,7)) |>
    st_as_sf(coords=c("lon","lat"), crs=4326) |> st_transform(2263)
}
urin <- load_pts("nypd_oath_urination_hxbk-grd3_20260920.csv")
alco <- load_pts("nypd_oath_alcohol_placebo_hxbk-grd3_20260920.csv")
hit <- function(p, nm) st_join(p, buf, join=st_within, left=FALSE) |> st_drop_geometry() |>
  count(fid, ym, name=nm)
hu <- hit(urin,"urin"); ha <- hit(alco,"alco")
cat("urination summonses within 250m of a facility:", sum(hu$urin),
    " | alcohol:", sum(ha$alco), "\n")

months <- format(seq(as.Date("2023-01-01"), as.Date("2026-06-01"), by="month"), "%Y-%m")
pan <- expand_grid(fid=rr$fid, ym=months) |>
  left_join(hu, by=c("fid","ym")) |> left_join(ha, by=c("fid","ym")) |>
  mutate(urin=replace_na(urin,0L), alco=replace_na(alco,0L)) |>
  left_join(rr |> dplyr::select(fid, open), by="fid") |>
  left_join(pac, by="fid") |>
  mutate(park_ac=replace_na(park_ac,0),
         mo=as.integer(substr(ym,6,7)),
         winter=as.integer(mo %in% c(12,1,2,3)),
         seasonal=as.integer(open=="Seasonal"),
         fid=factor(fid), ym=factor(ym), l_park=log1p(park_ac))
cat("panel:", nrow(pan), "facility-months | facilities:", nlevels(pan$fid),
    "| mean urination/month:", round(mean(pan$urin),3), "\n\n")

keep <- pan |> group_by(fid) |> summarise(t=sum(urin), .groups="drop") |> filter(t>0)
p <- pan |> filter(fid %in% keep$fid) |> mutate(fid=droplevels(fid))
cat("facilities with any nearby urination summons:", nlevels(p$fid), "\n")

# COLLAPSE to facility x season. Same DiD estimand, tractable to fit.
cs <- p |> group_by(fid, seasonal, l_park, winter) |>
  summarise(urin=sum(urin), alco=sum(alco), nm=n(), .groups="drop")
cat("collapsed panel:", nrow(cs), "rows (facility x winter/non-winter)\n")
cat("seasonal facilities in sample:", n_distinct(cs$fid[cs$seasonal==1]),
    "| year-round:", n_distinct(cs$fid[cs$seasonal==0]), "\n\n")

cl <- function(fit, g){
  ok <- !is.na(coef(fit))
  X <- model.matrix(fit)[, ok, drop=FALSE]; u <- X*(fit$y-fitted(fit)); uc <- rowsum(u, g)
  G <- length(unique(g)); b <- summary(fit)$cov.unscaled
  sqrt(diag(b %*% crossprod(uc) %*% b * (G/(G-1))))
}
run <- function(dv, lab, extra=""){
  f <- as.formula(paste0(dv," ~ winter*seasonal", extra, " + fid + offset(log(nm))"))
  m <- glm(f, family=poisson, data=cs)
  s <- cl(m, cs$fid); cf <- coef(m)[!is.na(coef(m))]
  k <- which(names(cf)=="winter:seasonal")
  b <- cf[k]; e <- s[k]
  cat(sprintf("%-44s IRR %.3f  (95%% CI %.3f-%.3f)  p=%.4f\n",
      lab, exp(b), exp(b-1.96*e), exp(b+1.96*e), 2*pnorm(-abs(b/e))))
}
cat("=== WINTERIZATION DiD ===\n")
cat("Winter effect on SEASONAL (closed in winter) vs YEAR-ROUND facilities, 250m catchment.\n")
cat("If closing a restroom matters, urination summonses should RISE (IRR > 1).\n\n")
run("urin","1. Urination summonses  [MAIN]")
run("urin","2. + park acreage x winter control"," + winter:l_park")
run("alco","3. PLACEBO: alcohol summonses")
run("alco","4. PLACEBO + park control"," + winter:l_park")
cat("\nA credible result needs (1) IRR>1 and significant, (2) surviving the park control,\n")
cat("and (3) the placebo showing NO effect.\n")
saveRDS(cs, file.path(D,"winterization_collapsed_20260920.rds"))
