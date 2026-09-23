# T1_mechanism_tests.R -- mechanism tests A-E (2026-09-23, mechanism-tests subagent)
#
# Tests the causal story the site tells, rather than the ranking itself.
#   A. Does EVENING supply predict complaints once crowds are controlled?  (audit gap G2)
#   B. Does the evening mechanism show up in complaint TIMING?
#   C. Cost per excess complaint assumes each fix removes ALL excess: break-even shares. (G3)
#   D. Capital project durations by type (reconstruct vs new build), anchored regex. (G8)
#   E. Parkland vs need in capital allocation (40_logistic.R), robustness.
# F (pilot power) is R/T1_F_pilot_power.R.
#
# READS ONLY data_raw/ and existing model tables. WRITES ONLY outputs/t1_tests_AE.{json,csv}
# (T1_F writes t1_tests_F.*; T1_F then merges both into outputs/t1_tests.{json,csv}).
# Does not modify any existing script's output.
#
# HOURS. 641 of 975 operational restrooms carry "8am-4pm, Open later seasonally". As in
# C2_hub_open_access.R: off_season close 16:00, in_season close 20:00, late (sensitivity
# only) 22:00. NOTE: at 21:00 the off- and in-season scenarios are IDENTICAL (both close
# before 9pm), so the only 9pm sensitivity that moves anything is the 22:00 one; at 18:00
# the off/in scenarios differ and are both run. Unparseable/blank hours = closed.
# Weekday = Wednesday (day_of_week 4, 1 = Sunday in parse_hours.R), as in C2.
# ---------------------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(dplyr); library(sf); library(MASS); library(sandwich); library(jsonlite)})
PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D <- file.path(PROJ, "data_raw"); OUT <- file.path(PROJ, "outputs")
set.seed(6093)
NSPLIT <- 200; WED <- 4; R400_FT <- 400/0.3048
PLACEHOLDER <- "8am-4pm, Open later seasonally"
SCEN <- c(off = 16, ins = 20, late = 22)

RES <- list(); ROWS <- list()
row <- function(test, item, est=NA, lo=NA, hi=NA, p=NA, n=NA, note="") {
  ROWS[[length(ROWS)+1]] <<- data.frame(test=test, item=item, estimate=est, lo=lo, hi=hi, p=p, n=n, note=note)
}

## ---- clustered SEs for NB (identical to 80_corrections.R) --------------------------
cl_nb_V <- function(fit, cl){
  X <- model.matrix(fit); mu <- fitted(fit); y <- fit$y; th <- fit$theta
  u <- X * ((y-mu)/(1+mu/th)); uc <- rowsum(u, cl); G <- length(unique(cl))
  vcov(fit) %*% crossprod(uc) %*% vcov(fit) * (G/(G-1))
}
irr_tab <- function(fit, cl, terms){
  V <- cl_nb_V(fit, cl); b <- coef(fit); se <- sqrt(diag(V))
  do.call(rbind, lapply(terms, function(t) data.frame(term=t, IRR=exp(b[t]),
    lo=exp(b[t]-1.96*se[t]), hi=exp(b[t]+1.96*se[t]), p=2*pnorm(-abs(b[t]/se[t])))))
}

## ======================================================================================
## 0. DATA
## ======================================================================================
d <- read.csv(file.path(D, "model_nta_scored_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total > 0) |> mutate(boro = factor(boro))
stopifnot(nrow(d) == 197)
nta_all <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |> st_transform(2263)
nta <- nta_all |> filter(ntatype == 0) |> dplyr::select(nta2020) |> st_make_valid()
nta <- nta[match(d$nta2020, nta$nta2020), ]; stopifnot(identical(nta$nta2020, d$nta2020))
nta_area <- as.numeric(st_area(nta))

to_nta <- function(sfp){   # residential NTA, snap strays to nearest (10_modelling_table.R rule)
  j <- st_join(sfp, nta, join = st_within)
  miss <- is.na(j$nta2020); if (any(miss)) j$nta2020[miss] <- nta$nta2020[st_nearest_feature(j[miss,], nta)]
  stopifnot(nrow(j) == nrow(sfp)); j$nta2020
}

rr <- read.csv(file.path(D, "nycrestrooms_i7jb-7jku_20260920.csv")); rr$facility_id <- seq_len(nrow(rr))
ph <- read.csv(file.path(D, "parsed_hours_20260920.csv"))
stopifnot(all(ph$facility_name[ph$day_of_week == 1] == rr$facility_name))   # row-key join check (as C2)
op <- rr[rr$status == "Operational" & !is.na(rr$latitude), ]
stopifnot(nrow(op) == 975)
ph <- ph[ph$facility_id %in% op$facility_id, ]
ph$placeholder <- ph$facility_id %in% op$facility_id[op$hours_of_operation == PLACEHOLDER]
ph$is24 <- ph$parsed & ph$is_open %in% TRUE & ph$open_hour == 0 & ph$close_hour >= 24
n_ph <- sum(op$hours_of_operation == PLACEHOLDER); stopifnot(n_ph == 641)
open_ids <- function(h, dow, ph_close, placeholder_open = TRUE){
  p <- ph[ph$day_of_week == dow & ph$parsed & ph$is_open %in% TRUE, ]
  p$close_hour[p$placeholder] <- ph_close
  if (!placeholder_open) p <- p[!p$placeholder, ]
  if (h < 24) unique(p$facility_id[p$open_hour <= h & p$close_hour > h])
  else unique(p$facility_id[p$close_hour > 24 | p$is24])
}
op_sf <- st_as_sf(op, coords = c("longitude","latitude"), crs = 4326) |> st_transform(2263)
op_sf$nta2020 <- to_nta(op_sf)
op_sf$park <- op_sf$location_type == "Park"
cat("operational restrooms:", nrow(op_sf), " in parks:", sum(op_sf$park), " placeholder:", n_ph, "\n")

nta_buf <- st_buffer(nta, R400_FT)            # "near": inside the NTA or within 400 m of it
count_in <- function(ids) as.numeric(table(factor(op_sf$nta2020[op_sf$facility_id %in% ids], levels = d$nta2020)))
count_near <- function(ids){ pts <- op_sf[op_sf$facility_id %in% ids, ]
  lengths(st_intersects(nta_buf, pts)) }
coverage <- function(ids){                    # % NTA land within 400 m straight line of an open restroom
  pts <- op_sf[op_sf$facility_id %in% ids, ]; if (!nrow(pts)) return(rep(0, nrow(nta)))
  buf <- st_union(st_buffer(pts, R400_FT))
  ii <- suppressWarnings(st_intersection(nta, buf)); a <- as.numeric(st_area(ii))
  v <- tapply(a, ii$nta2020, sum)[d$nta2020]; v[is.na(v)] <- 0; 100 * as.numeric(v) / nta_area
}

ids <- list(
  all      = op$facility_id,
  h15      = open_ids(15, WED, SCEN["off"]),                     # placeholders open at 3pm in all scenarios
  h15_expl = open_ids(15, WED, SCEN["off"], placeholder_open = FALSE),   # B1's convention
  h18_off  = open_ids(18, WED, SCEN["off"]),
  h18_ins  = open_ids(18, WED, SCEN["ins"]),
  h21      = open_ids(21, WED, SCEN["off"]),
  h21_ins  = open_ids(21, WED, SCEN["ins"]),
  h21_late = open_ids(21, WED, SCEN["late"]))
stopifnot(setequal(ids$h21, ids$h21_ins))
cat("open on Wednesday: 3pm", length(ids$h15), " 6pm off/in", length(ids$h18_off), "/", length(ids$h18_ins),
    " 9pm", length(ids$h21), " 9pm (22:00 placeholder)", length(ids$h21_late), "\n")
RES$hours_counts <- lapply(ids, length)

d$n_open21      <- count_in(ids$h21);  d$n_open21_late <- count_in(ids$h21_late)
d$n_open18_off  <- count_in(ids$h18_off); d$n_open18_ins <- count_in(ids$h18_ins)
d$n_open21_near <- count_near(ids$h21); d$n_open21_late_near <- count_near(ids$h21_late)
d$n_all_op      <- count_in(ids$all)
d$n_park        <- as.numeric(table(factor(op_sf$nta2020[op_sf$park], levels = d$nta2020)))
d$n_nonpark     <- d$n_all_op - d$n_park
d$park_share    <- ifelse(d$n_all_op > 0, d$n_park / d$n_all_op, 0)
cat("computing coverage (5 hour sets)...\n")
d$cov15 <- coverage(ids$h15); d$cov15_expl <- coverage(ids$h15_expl)
d$cov18_off <- coverage(ids$h18_off); d$cov18_ins <- coverage(ids$h18_ins)
d$cov21 <- coverage(ids$h21); d$cov21_late <- coverage(ids$h21_late)
cat(sprintf("mean NTA coverage: 3pm %.1f%% (explicit-hours only %.1f%%) | 6pm off %.1f%% in %.1f%% | 9pm %.1f%% (late %.1f%%)\n",
    mean(d$cov15), mean(d$cov15_expl), mean(d$cov18_off), mean(d$cov18_ins), mean(d$cov21), mean(d$cov21_late)))
cat("NTAs with ANY restroom open at 9pm inside:", sum(d$n_open21 > 0), " of 197; within 400 m:", sum(d$n_open21_near > 0), "\n")
d <- d |> mutate(l_open21 = log1p(n_open21), l_open21_late = log1p(n_open21_late),
  l_open18_off = log1p(n_open18_off), l_open18_ins = log1p(n_open18_ins),
  l_open21_near = log1p(n_open21_near), l_open21_late_near = log1p(n_open21_late_near),
  l_park_r = log1p(n_park), l_nonpark_r = log1p(n_nonpark),
  c15 = cov15/10, c21 = cov21/10, c21_late = cov21_late/10, c15_expl = cov15_expl/10)
RES$supply_descriptives <- list(
  mean_cov15 = mean(d$cov15), mean_cov15_explicit_only = mean(d$cov15_expl),
  mean_cov18_off = mean(d$cov18_off), mean_cov18_ins = mean(d$cov18_ins),
  mean_cov21 = mean(d$cov21), mean_cov21_late = mean(d$cov21_late),
  ntas_open21_inside = sum(d$n_open21 > 0), ntas_open21_near = sum(d$n_open21_near > 0),
  cor_lrest_lopen21 = cor(d$l_rest, d$l_open21), cor_cov15_cov21 = cor(d$cov15, d$cov21),
  park_share_mean_nta = mean(d$park_share[d$n_all_op > 0]))

## ======================================================================================
## A. DOES EVENING SUPPLY MATTER?
## ======================================================================================
cat("\n================ A. evening supply in the NTA model ================\n")
BASE <- "l_sub + l_jobs + l_hotel + l_dens + inc10k + pov + old + boro + offset(log(pop_total))"
mk <- function(supply) as.formula(paste("events_311 ~", supply, "+", BASE))
SPECS <- list(
  M0_base            = list(s = "l_rest",                                  terms = "l_rest"),
  A1_open21_in       = list(s = "l_rest + l_open21",                       terms = c("l_rest","l_open21")),
  A1_open21_near     = list(s = "l_rest + l_open21_near",                  terms = c("l_rest","l_open21_near")),
  A1_open21_late_in  = list(s = "l_rest + l_open21_late",                  terms = c("l_rest","l_open21_late")),
  A1_open21_late_near= list(s = "l_rest + l_open21_late_near",             terms = c("l_rest","l_open21_late_near")),
  A1_open18_off_in   = list(s = "l_rest + l_open18_off",                   terms = c("l_rest","l_open18_off")),
  A1_open18_ins_in   = list(s = "l_rest + l_open18_ins",                   terms = c("l_rest","l_open18_ins")),
  A1_open21_only     = list(s = "l_open21_near",                           terms = "l_open21_near"),
  A2_park_share      = list(s = "l_rest + park_share",                     terms = c("l_rest","park_share")),
  A2_park_split      = list(s = "l_park_r + l_nonpark_r",                  terms = c("l_park_r","l_nonpark_r")),
  A3_cov_day_eve     = list(s = "l_rest + c15 + c21",                      terms = c("l_rest","c15","c21")),
  A3_cov_day_eve_late= list(s = "l_rest + c15 + c21_late",                 terms = c("l_rest","c15","c21_late")),
  A3_cov_explicit    = list(s = "l_rest + c15_expl + c21",                 terms = c("l_rest","c15_expl","c21")),
  A4_all             = list(s = "l_rest + l_open21_near + park_share + c15 + c21",
                            terms = c("l_rest","l_open21_near","park_share","c15","c21")))
A_irr <- list(); fits <- list()
for (nm in names(SPECS)) {
  f <- glm.nb(mk(SPECS[[nm]]$s), data = d); fits[[nm]] <- f
  t <- irr_tab(f, d$cdta2020, SPECS[[nm]]$terms); t$spec <- nm; t$aic <- AIC(f); A_irr[[nm]] <- t
  for (k in seq_len(nrow(t))) row("A", paste(nm, t$term[k], sep=":"), t$IRR[k], t$lo[k], t$hi[k], t$p[k], nrow(d),
                                  sprintf("NB IRR per unit; CD-clustered 95%% CI; AIC %.1f", AIC(f)))
}
A_irr <- do.call(rbind, A_irr); rownames(A_irr) <- NULL
print(A_irr |> mutate(across(c(IRR,lo,hi), ~round(.x,3)), p = round(p,3), aic = round(aic,1)), row.names = FALSE)

cat("\nOut-of-sample: 200 identical 70/30 splits, Spearman(pred, actual) vs ridership rule\n")
oos <- replicate(NSPLIT, {
  i <- sample(nrow(d), round(0.7*nrow(d))); tr <- d[i,]; te <- d[-i,]
  r <- sapply(names(SPECS), function(nm){ fit <- try(glm.nb(mk(SPECS[[nm]]$s), data = tr), silent = TRUE)
    if (inherits(fit, "try-error")) return(NA)
    pm <- try(predict(fit, newdata = te, type = "response"), silent = TRUE)
    if (inherits(pm, "try-error")) NA else cor(pm, te$events_311, method = "spearman") })
  c(r, benchmark = cor(te$subway_riders, te$events_311, method = "spearman"))
})
ok <- colSums(is.na(oos)) == 0; oos <- oos[, ok, drop = FALSE]
A_oos <- data.frame(spec = rownames(oos), mean_rho = rowMeans(oos),
  diff_vs_M0 = rowMeans(oos - matrix(oos["M0_base",], nrow(oos), ncol(oos), byrow = TRUE)),
  share_splits_better_than_M0 = rowMeans(oos > matrix(oos["M0_base",], nrow(oos), ncol(oos), byrow = TRUE)),
  share_beats_benchmark = rowMeans(oos > matrix(oos["benchmark",], nrow(oos), ncol(oos), byrow = TRUE)))
cat("valid splits:", ncol(oos), "\n")
print(A_oos |> mutate(across(where(is.numeric), ~round(.x, 3))), row.names = FALSE)
for (k in seq_len(nrow(A_oos))) row("A_oos", A_oos$spec[k], A_oos$mean_rho[k], NA, NA, NA, ncol(oos),
  sprintf("mean OOS Spearman; diff vs M0 %+.4f; better than M0 in %.0f%% of splits; beats ridership in %.0f%%",
          A_oos$diff_vs_M0[k], 100*A_oos$share_splits_better_than_M0[k], 100*A_oos$share_beats_benchmark[k]))
RES$A <- list(irr = A_irr, oos = A_oos, valid_splits = ncol(oos))

## ======================================================================================
## B. DOES THE EVENING MECHANISM SHOW UP IN TIMING?
## ======================================================================================
cat("\n================ B. evening share of complaints ================\n")
ev <- read.csv(file.path(D, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
u <- ev[ev$complaint_type == "Urinating in Public" & ev$location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"), ]
u$ym <- substr(u$created_date, 1, 7)
u <- u[is.finite(suppressWarnings(as.numeric(u$latitude))), ]
cm <- u[!duplicated(u[, c("incident_address","ym")]), ]; stopifnot(nrow(cm) == 3629)
cm$hour <- as.integer(substr(cm$created_date, 12, 13))
cm$dow <- as.POSIXlt(as.Date(substr(cm$created_date, 1, 10)))$wday + 1       # 1 = Sunday
cm_sf <- st_as_sf(cm, coords = c("longitude","latitude"), crs = 4326) |> st_transform(2263)
jj <- st_join(cm_sf, nta_all |> dplyr::select(nta2020, ntatype), join = st_within)
cm$nta2020 <- ifelse(jj$ntatype %in% 0, jj$nta2020, NA)       # model convention: residential NTAs only
cat("complaints in residential NTAs:", sum(!is.na(cm$nta2020)), "(model total", sum(d$events_311), ")\n")
cm$eve <- cm$hour >= 18
tb <- cm |> filter(!is.na(nta2020)) |> group_by(nta2020) |> summarise(n = n(), n_eve = sum(eve), .groups = "drop")
db <- d |> inner_join(tb, by = "nta2020") |>
  mutate(collapse = (cov15 - cov21)/10, collapse_late = (cov15 - cov21_late)/10,
         lost_share = ifelse(cov15 > 0, 1 - cov21/cov15, NA))
cat("NTAs with >=1 complaint:", nrow(db), "  overall evening share:", round(100*sum(db$n_eve)/sum(db$n),1), "%\n")
cat("cor(collapse, daytime coverage) =", round(cor(db$collapse, db$c15), 3),
    " -- collapse is almost all daytime coverage, because 9pm coverage is near zero everywhere\n")
bfit <- function(fm, dat){
  g <- glm(fm, family = quasibinomial, data = dat, weights = n)
  V <- vcovCL(g, cluster = dat$cdta2020); list(g = g, V = V)
}
B_specs <- list(   # first term is the one reported
  B1_collapse_ctrl_day  = "collapse + c15 + l_sub + l_jobs + l_dens + boro",
  B1_collapse_nocontrol = "collapse + l_sub + l_jobs + l_dens + boro",
  B1_late_ctrl_day      = "collapse_late + c15 + l_sub + l_jobs + l_dens + boro",
  B2_lost_share         = "lost_share + c15 + l_sub + l_jobs + l_dens + boro",
  B3_open21_near        = "l_open21_near + l_rest + l_sub + l_jobs + l_dens + boro",
  B4_cov21_ctrl_day     = "c21 + c15 + l_sub + l_jobs + l_dens + boro")
B_tab <- list()
for (nm in names(B_specs)) {
  fm <- as.formula(paste("I(n_eve/n) ~", B_specs[[nm]]))
  k <- trimws(strsplit(B_specs[[nm]], "\\+")[[1]][1])
  vars <- setdiff(all.vars(fm), c("n_eve"))
  dat <- db[complete.cases(db[, vars]), ]
  o <- bfit(fm, dat); b <- coef(o$g)[k]; se <- sqrt(o$V[k,k])
  B_tab[[nm]] <- data.frame(spec = nm, term = k, OR = exp(b), lo = exp(b-1.96*se), hi = exp(b+1.96*se),
                            p = 2*pnorm(-abs(b/se)), n_nta = nrow(dat), n_complaints = sum(dat$n))
  row("B", paste(nm, k, sep=":"), exp(b), exp(b-1.96*se), exp(b+1.96*se), 2*pnorm(-abs(b/se)), nrow(dat),
      "odds ratio of a complaint being filed 18:00-23:59; per 10pp coverage (or per unit); quasibinomial weighted by complaints, CD-clustered")
}
B_tab <- do.call(rbind, B_tab); rownames(B_tab) <- NULL
print(B_tab |> mutate(across(c(OR,lo,hi), ~round(.x,3)), p = round(p,3)), row.names = FALSE)
# plain-language effect size: predicted evening share at low vs high collapse (IQR)
g1 <- glm(I(n_eve/n) ~ collapse + c15 + l_sub + l_jobs + l_dens + boro, family = quasibinomial, data = db, weights = n)
q <- quantile(db$collapse, c(.25,.75)); nd <- db; nd$collapse <- q[1]; p25 <- weighted.mean(predict(g1, nd, type="response"), db$n)
nd$collapse <- q[2]; p75 <- weighted.mean(predict(g1, nd, type="response"), db$n)
cat(sprintf("Predicted evening share, collapse at P25 (%.1f pp) vs P75 (%.1f pp), holding the rest: %.1f%% vs %.1f%%\n",
            10*q[1], 10*q[2], 100*p25, 100*p75))
row("B", "evening_share_P25_vs_P75_collapse", 100*(p75-p25), NA, NA, NA, nrow(db),
    sprintf("pp difference in predicted evening share (%.1f%% at P25 vs %.1f%% at P75)", 100*p25, 100*p75))

## citywide hour profile vs restrooms open that hour (averaged over 7 days)
hrs <- 0:23
open_by_hour <- function(close) sapply(hrs, function(h) mean(sapply(1:7, function(dw) length(open_ids(h, dw, close)))))
oh_off <- open_by_hour(SCEN["off"]); oh_ins <- open_by_hour(SCEN["ins"])
cp <- as.numeric(table(factor(cm$hour, levels = hrs))); cp_share <- cp/sum(cp)
d2 <- read.csv(file.path(D, "nyc311_dirtycondition_erm2-nwe9_20260920.csv"))
dh <- as.integer(substr(d2$created_date, 12, 13)); dp <- as.numeric(table(factor(dh, levels = hrs))); dp_share <- dp/sum(dp)
rel <- cp_share / dp_share             # urination share relative to another 311 type (same calling habits)
prof <- data.frame(hour = hrs, complaints = cp, share = round(100*cp_share, 2),
                   dirty_share = round(100*dp_share, 2), relative_to_dirty = round(rel, 3),
                   open_off = round(oh_off, 1), open_ins = round(oh_ins, 1))
print(prof, row.names = FALSE)
awake <- hrs >= 7
cc <- c(cor_share_open_off = cor(cp_share, oh_off), cor_share_open_ins = cor(cp_share, oh_ins),
        cor_rel_open_off_7to23 = cor(rel[awake], oh_off[awake]), cor_rel_open_ins_7to23 = cor(rel[awake], oh_ins[awake]),
        cor_share_open_off_7to23 = cor(cp_share[awake], oh_off[awake]))
print(round(cc, 3))
for (k in names(cc)) row("B_hourly", k, cc[[k]], NA, NA, NA, 24, "Pearson across hours; open = mean over 7 days")
ev_share <- sum(cp[19:24])/sum(cp); dev_share <- sum(dp[19:24])/sum(dp)
row("B_hourly", "evening_share_urination", 100*ev_share, NA, NA, NA, sum(cp), "% filed 18:00-23:59, de-duplicated 3,629")
row("B_hourly", "evening_share_dirty_condition", 100*dev_share, NA, NA, NA, sum(dp), "% filed 18:00-23:59, DSNY Dirty Condition (calling-habit control)")
RES$B <- list(models = B_tab, p25_p75 = c(p25 = p25, p75 = p75, collapse_p25 = 10*q[1], collapse_p75 = 10*q[2]),
              hourly = prof, hourly_cor = as.list(cc), evening_share = ev_share, evening_share_dirty = dev_share,
              cor_collapse_c15 = cor(db$collapse, db$c15), n_nta = nrow(db))

## ======================================================================================
## C. BREAK-EVEN EFFECTIVENESS FOR THE COST RANKING
## ======================================================================================
cat("\n================ C. break-even effectiveness ================\n")
sh <- read.csv(file.path(D, "model_shortlist_costed_20260920.csv"))
YRS <- 6.71
annualise <- function(capex, life, r = 0.03) capex * (r*(1+r)^life)/((1+r)^life - 1)
iv <- read.csv(file.path(D, "model_nta_interventions_20260920.csv"))
CAP_MOD <- unique(iv$capex[iv$intervention == "Build new / modular unit" & !is.na(iv$capex)])
CAP_REC <- unique(iv$capex[iv$intervention == "Reconstruct or repair" & !is.na(iv$capex)])
COST <- c(hours = 4*365*35, modular = annualise(CAP_MOD, 20), reconstruct = annualise(CAP_REC, 20))
stopifnot(all.equal(unname(COST["hours"]), unique(sh$annual_cost[sh$intervention == "Extend operating hours"])),
          all.equal(unname(COST["modular"]), unique(sh$annual_cost[sh$intervention == "Build new / modular unit"])))
print(round(COST))
rel <- c(hours_vs_modular = COST[["hours"]]/COST[["modular"]], hours_vs_reconstruct = COST[["hours"]]/COST[["reconstruct"]],
         modular_vs_reconstruct = COST[["modular"]]/COST[["reconstruct"]])
cat("Same-area break-even (option A must remove at least this share of what B removes):\n"); print(round(rel, 3))
for (k in names(rel)) row("C", paste0("breakeven_relative_", k), rel[[k]], NA, NA, NA, NA,
  "one facility per area; denominator (excess) is common so the threshold is the same in every area")
key <- c("Extend operating hours" = "hours", "Build new / modular unit" = "modular", "Reconstruct or repair" = "reconstruct")
sc <- sh |> filter(intervention %in% names(key)) |>
  mutate(opt = key[intervention], excess_yr = excess/YRS, per_excess_yr = annual_cost/excess_yr,
         cost_hours_yr = COST["hours"]/excess_yr, cost_modular_yr = COST["modular"]/excess_yr,
         cost_reconstruct_yr = COST["reconstruct"]/excess_yr) |> arrange(per_excess_yr)
stopifnot(nrow(sc) == 27)
sc$rank100 <- seq_len(nrow(sc))
# share of annual excess each area's option must remove to remain cheaper per avoided complaint than
# the best OTHER area at full effectiveness (i.e. to be the programme's first buy)
sc$f_to_be_first <- sapply(seq_len(nrow(sc)), function(i) sc$per_excess_yr[i] / min(sc$per_excess_yr[-i]))
sc$f_vs_next_rank <- c(sc$per_excess_yr[-nrow(sc)] / sc$per_excess_yr[-1], NA)
rank_under <- function(eh){ pe <- sc$per_excess_yr / ifelse(sc$opt == "hours", eh, 1); rank(pe, ties.method = "first") }
for (eh in c(1, .75, .5, .25)) sc[[paste0("rank_h", 100*eh)]] <- rank_under(eh)
print(sc |> transmute(area = substr(ntaname,1,28), opt, excess_yr = round(excess_yr,1),
  per_excess_yr = round(per_excess_yr), f_to_be_first = round(f_to_be_first,2),
  rank100, rank_h50, rank_h25), row.names = FALSE)
C_scen <- lapply(c(1, .75, .5, .25), function(eh){
  r <- sc[[paste0("rank_h", 100*eh)]]; top <- sc$ntaname[order(r)]
  list(hours_effectiveness = eh, first = top[1], top5 = head(top, 5),
       hours_areas_in_top6 = sum(sc$opt[order(r)][1:6] == "hours"),
       spearman_vs_full = cor(r, sc$rank100, method = "spearman"),
       east_harlem_rank = r[sc$ntaname == "East Harlem (North)"],
       cheapest_per_excess_yr = min(sc$per_excess_yr / ifelse(sc$opt == "hours", eh, 1))) })
for (s in C_scen) { cat(sprintf("hours at %3.0f%%: first = %s; hours areas in top 6 = %d; East Harlem rank %d; Spearman vs 100%% %.3f\n",
    100*s$hours_effectiveness, s$first, s$hours_areas_in_top6, s$east_harlem_rank, s$spearman_vs_full))
  row("C", sprintf("ranking_hours_%d_pct", round(100*s$hours_effectiveness)), s$spearman_vs_full, NA, NA, NA, 27,
      sprintf("Spearman vs full-effect ranking; first = %s; East Harlem rank %d; hours areas in top 6 = %d",
              s$first, s$east_harlem_rank, s$hours_areas_in_top6)) }
eh_i <- which(sc$ntaname == "East Harlem (North)")
row("C", "east_harlem_hours_share_needed_to_stay_first", sc$f_to_be_first[eh_i], NA, NA, NA, NA,
    "share of East Harlem's annual excess extended hours must remove to stay cheaper than the next-best area at 100%")
row("C", "east_harlem_per_excess_yr", sc$per_excess_yr[eh_i], NA, NA, NA, NA, "USD per excess complaint per year at 100% removal")
# external evidence scale: excess per area-year vs SF literature
row("C", "median_excess_per_area_year", median(sc$excess_yr), NA, NA, NA, 27,
    "excess complaints per year per shortlisted area; Amato 2022 SF: ~50 fewer reports per new facility-year, but +12.00/week after 3 sites extended hours (p=0.0016; confounded by site choice)")
RES$C <- list(costs = as.list(COST), relative_breakeven = as.list(rel), areas = sc, scenarios = C_scen,
  sf_caveat = "Amato et al. 2022 (BMC Public Health, SF Pit Stop, Table 1): 3 sites that expanded to 24h were followed by +12.00 feces reports/week within 500 m (p=0.0016). Sites chosen for longer hours were the busiest, so this is confounded, not a causal harm estimate - but it is the only external estimate for the hours lever and it has the wrong sign.")

## ======================================================================================
## D. CAPITAL PROJECT DURATIONS BY TYPE
## ======================================================================================
cat("\n================ D. capital durations by type ================\n")
ct_raw <- read.csv(file.path(D, "capitaltracker_4hcv-tc5r_20260920.csv"))
ct <- ct_raw |> distinct(trackerid, .keep_all = TRUE) |>
  filter(grepl("restroom|comfort station|bathroom", paste(title, summary), ignore.case = TRUE))
cat("tracker rows:", nrow(ct_raw), " restroom projects after trackerid dedup:", nrow(ct), "\n")
tx <- tolower(paste(ct$title, ct$summary)); RM <- "restroom|comfort station|bathroom"
# A7 classification (as-is)
recA <- grepl(paste0("(",RM,")[a-z ]*reconstruction"), tx)
newA <- grepl(paste0("(",RM,")[a-z ]*construction"), tx) & !recA
# anchored: "construction" must be a whole word (not the tail of "reconstruction")
recB <- grepl(paste0("(",RM,")[a-z ]*\\breconstruction\\b"), tx)
newB <- grepl(paste0("(",RM,")[a-z ]*\\bconstruction\\b"), tx) & !recB
newB_strict <- grepl(paste0("(",RM,")[a-z ]*\\bconstruction\\b"), tx) &
               !grepl(paste0("(",RM,")[a-z ]*\\breconstruction\\b"), tx)
s <- as.Date(substr(ct$designstart, 1, 10)); f <- as.Date(substr(ct$constructionactualcompletion, 1, 10))
yrs <- as.numeric(f - s)/365.25; okd <- is.finite(yrs) & yrs > 0
summ <- function(lab, sel){ y <- yrs[sel & okd]
  data.frame(classification = lab, n_projects = sum(sel), n_completed = length(y), median = median(y),
             q1 = unname(quantile(y, .25)), q3 = unname(quantile(y, .75))) }
D_tab <- rbind(summ("pooled (all restroom projects)", rep(TRUE, nrow(ct))),
  summ("A7 regex: reconstruct", recA), summ("A7 regex: build new", newA),
  summ("anchored \\b: reconstruct", recB), summ("anchored \\b: build new", newB_strict),
  summ("other / unclear (anchored)", !recB & !newB_strict))
print(D_tab |> mutate(across(c(median,q1,q3), ~round(.x,2))), row.names = FALSE)
cat("A7 vs anchored classification agree on", sum((recA == recB) & (newA == newB_strict)), "of", nrow(ct), "projects\n")
cat("phrases that are 'construction' inside a restroom phrase but ALSO contain 'reconstruction' elsewhere (A7 counts as recon):",
    sum(newB & recB), "\n")
wt <- wilcox.test(yrs[recB & okd], yrs[newB_strict & okd])
cat(sprintf("Wilcoxon reconstruct vs new build: p = %.4f\n", wt$p.value))
for (k in seq_len(nrow(D_tab))) row("D", D_tab$classification[k], D_tab$median[k], D_tab$q1[k], D_tab$q3[k],
  NA, D_tab$n_completed[k], sprintf("median years design start -> construction actual completion; lo/hi = IQR; %d projects of this type", D_tab$n_projects[k]))
row("D", "wilcoxon_recon_vs_new", NA, NA, NA, wt$p.value, NA, "rank-sum test of durations, anchored classification")
RES$D <- list(table = D_tab, wilcoxon_p = wt$p.value, agree = sum((recA == recB) & (newA == newB_strict)), n = nrow(ct))

## ======================================================================================
## E. PARKLAND VS NEED IN CAPITAL ALLOCATION
## ======================================================================================
cat("\n================ E. parkland vs need ================\n")
inv <- read.csv(file.path(D, "model_nta_investment_20260920.csv")) |> mutate(boro = factor(boroname))
stopifnot(nrow(inv) == 197)
cat("received >=1 restroom capital project:", sum(inv$got), " of", nrow(inv), "\n")
E_specs <- list(
  E0_as_40      = got ~ need + l_sub + l_jobs + l_park + poverty_rate + boro,
  E1_no_park    = got ~ need + l_sub + l_jobs + poverty_rate + boro,
  E2_no_boroFE  = got ~ need + l_sub + l_jobs + l_park + poverty_rate,
  E3_need_only  = got ~ need,
  E4_need_boro  = got ~ need + boro,
  E5_park_only  = got ~ l_park + boro,
  E6_lneed      = got ~ log1p(need) + l_sub + l_jobs + l_park + poverty_rate + boro,
  E7_need_abs   = got ~ log1p(need_abs) + l_sub + l_jobs + l_park + poverty_rate + boro,
  E7b_abs_pop   = got ~ log1p(need_abs) + log(pop_total) + l_sub + l_jobs + l_park + poverty_rate + boro,
  E8_plus_rest  = got ~ need + l_sub + l_jobs + l_park + poverty_rate + l_rest + boro)
E_tab <- list()
for (nm in names(E_specs)) {
  g <- glm(E_specs[[nm]], family = binomial, data = inv)
  Vc <- vcovCL(g, cluster = inv$cdta2020, type = "HC0")
  for (k in intersect(c("need","log1p(need)","log1p(need_abs)","l_park","l_rest","poverty_rate","l_sub"), names(coef(g)))) {
    b <- coef(g)[k]; se_m <- sqrt(vcov(g)[k,k]); se_c <- sqrt(Vc[k,k])
    E_tab[[length(E_tab)+1]] <- data.frame(spec = nm, term = k, OR = exp(b),
      lo = exp(b-1.96*se_m), hi = exp(b+1.96*se_m), p = 2*pnorm(-abs(b/se_m)),
      lo_cl = exp(b-1.96*se_c), hi_cl = exp(b+1.96*se_c), p_cl = 2*pnorm(-abs(b/se_c)), aic = AIC(g))
    row("E", paste(nm, k, sep=":"), exp(b), exp(b-1.96*se_m), exp(b+1.96*se_m), 2*pnorm(-abs(b/se_m)), nrow(inv),
        sprintf("logit OR per unit (need = ratio, l_park = log1p acres); model-based Wald CI; CD-clustered p = %.4f [%.2f, %.2f]",
                2*pnorm(-abs(b/se_c)), exp(b-1.96*se_c), exp(b+1.96*se_c)))
  }
}
E_tab <- do.call(rbind, E_tab); rownames(E_tab) <- NULL
g0 <- glm(E_specs$E0_as_40, family = binomial, data = inv)
pov10 <- exp(0.1*coef(g0)["poverty_rate"]); pci <- exp(0.1*confint.default(g0)["poverty_rate",])
cat(sprintf("poverty per +10 points: OR %.2f [%.2f, %.2f]\n", pov10, pci[1], pci[2]))
row("E", "E0_as_40:poverty_per_10pp", pov10, pci[1], pci[2], NA, nrow(inv), "logit OR per +10 percentage points poverty")
print(E_tab |> mutate(across(c(OR,lo,hi,lo_cl,hi_cl), ~round(.x,3)), across(c(p,p_cl), ~round(.x,4)), aic = round(aic,1)), row.names = FALSE)
# descriptive: project rate by need tercile and park tercile
inv$need_t <- cut(inv$need, quantile(inv$need, 0:3/3), include.lowest = TRUE, labels = c("low","mid","high"))
inv$park_t <- cut(inv$park_acres, quantile(inv$park_acres, 0:3/3), include.lowest = TRUE, labels = c("low","mid","high"))
E_desc <- list(by_need = tapply(inv$got, inv$need_t, mean), by_park = tapply(inv$got, inv$park_t, mean),
               shortlist_29_rate = mean(inv$got[inv$need >= 1.5]), rest_rate = mean(inv$got[inv$need < 1.5]))
print(E_desc)
row("E", "project_rate_need_ge_1.5", E_desc$shortlist_29_rate, NA, NA, NA, sum(inv$need >= 1.5), "share of the 29 high-need areas with >=1 restroom capital project")
row("E", "project_rate_need_lt_1.5", E_desc$rest_rate, NA, NA, NA, sum(inv$need < 1.5), "share of other residential NTAs with >=1 project")
RES$E <- list(table = E_tab, descriptives = E_desc)

## ---- write -------------------------------------------------------------------------
tab <- do.call(rbind, ROWS)
write.csv(tab, file.path(OUT, "t1_tests_AE.csv"), row.names = FALSE)
write_json(RES, file.path(OUT, "t1_tests_AE.json"), auto_unbox = TRUE, digits = 6, pretty = TRUE, dataframe = "rows")
cat("\nwrote outputs/t1_tests_AE.{csv,json}:", nrow(tab), "rows\n")
