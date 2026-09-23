# Z0_headline_numbers.R — THE single source of truth for every headline number.
#
# Every figure below is DERIVED: read from data_raw/ or computed by sourcing the script
# that owns it (each in a fresh Rscript process, so it behaves exactly as when run alone).
# The only typed constants are genuine EXTERNAL facts, kept in a separate block with a URL.
# Modelling ASSUMPTIONS (wage, extra hours, $1.2M modular) are not typed here either:
# they are parsed out of the scripts that use them, so this file reports what the code
# actually does.
#
# Writes outputs/headline_numbers.json and outputs/headline_numbers.csv.
# Deterministic: no timestamps; fixed seeds live in the owning scripts.
# Prerequisite: the derived tables in data_raw/ must be current. Run order that rebuilds
# them: 10 -> 11 -> 20 -> 40 -> 60 -> 61 -> 95 -> 96 (all deterministic, ~1 min).
# Runtime of this script: ~25 s.
suppressMessages({library(dplyr); library(jsonlite)}); options(scipen=999)
P <- Sys.getenv("RESTROOM_PROJ", unset=".")
setwd(P); dd <- "data_raw"; dir.create("outputs", showWarnings=FALSE)
RS <- file.path(R.home("bin"), "Rscript")

## ---- helper: source a script in a clean process, return an expression's value --
from_script <- function(script, expr) {
  out <- tempfile(fileext=".rds")
  code <- sprintf('e <- new.env(); invisible(capture.output(suppressWarnings(suppressMessages(
      sys.source("R/%s", envir=e))))); saveRDS(eval(quote(%s), e), "%s")', script, expr, out)
  st <- system2(RS, c("-e", shQuote(code)), stdout=FALSE, stderr=FALSE)
  if (st != 0 || !file.exists(out)) stop("could not source R/", script)
  readRDS(out)
}
## ---- helper: read an assignment's value out of a script's source text ---------
from_code <- function(script, var) {
  tx <- readLines(file.path("R", script))
  m <- regmatches(tx, regexpr(paste0("\\b", var, "\\s*(<-|=)\\s*[0-9.e]+"), tx))
  if (!length(m)) stop(var, " not found in ", script)
  as.numeric(sub(".*(<-|=)\\s*", "", m[1]))
}

## ---- display formatting -------------------------------------------------------
comma <- function(x) format(round(x), big.mark=",", trim=TRUE)
usdM  <- function(x, d=1) sprintf("$%.*fM", d, x/1e6)
pct   <- function(x, d=0) sprintf("%.*f%%", d, 100*x)
f3    <- function(x) sprintf("%.3f", x)

H <- list()   # key -> list(value, display, unit, source, note, patterns)
add <- function(key, value, display, unit, source, note="", patterns=NULL)
  H[[key]] <<- list(value=value, display=display, unit=unit, source=source, note=note,
                    patterns=if (is.null(patterns)) character(0) else patterns)
# literal-number regex with digit boundaries (so 975 does not match 1975 or 9.75)
nrx <- function(s) paste0("(?<![0-9.,])", gsub("([.$()+*?])", "\\\\\\1", s), "(?![0-9]|,[0-9])")

## =============================================================================
## 1. MODEL vs BENCHMARK (out of sample)
## Canonical = 50_tree_vs_regression.R (seed 6093, 200 random 70/30 splits). It is the
## script the site already cites, and the only one that scores NB, tree and benchmark on
## the SAME splits. 20_regression.R uses the same seed but consumes the RNG differently
## and prints 0.786 / 0.704 / 94%; A3 shows the model lands 0.784-0.791 across six seeds.
## =============================================================================
oos <- from_script("50_tree_vs_regression.R", "res")
nspl <- ncol(oos); wins <- sum(oos["nb",] > oos["bench",])
add("model_oos_spearman", mean(oos["nb",]), f3(mean(oos["nb",])), "Spearman rho (mean)",
    "R/50_tree_vs_regression.R", sprintf("mean over %d splits, seed 6093", nspl),
    nrx(f3(mean(oos["nb",]))))
add("benchmark_oos_spearman", mean(oos["bench",]), f3(mean(oos["bench",])), "Spearman rho (mean)",
    "R/50_tree_vs_regression.R", "subway ridership alone, same splits", nrx(f3(mean(oos["bench",]))))
add("model_beats_benchmark_share", wins/nspl, pct(wins/nspl), "share of splits",
    "R/50_tree_vs_regression.R", sprintf("%d of %d splits. Canonical wording: '%s of %d splits'",
    wins, nspl, pct(wins/nspl), nspl), paste0(nrx(pct(wins/nspl)), "(?= of)"))
add("n_oos_splits", nspl, as.character(nspl), "splits", "R/50_tree_vs_regression.R",
    "random 70/30 train/test splits", paste0(nrx(as.character(nspl)), "(?= (random |times|trials|splits))"))
add("tree_oos_spearman", mean(oos["tree",]), f3(mean(oos["tree",])), "Spearman rho (mean)",
    "R/50_tree_vs_regression.R", "unpruned decision tree", nrx(f3(mean(oos["tree",]))))
add("tree_beats_benchmark_share", mean(oos["tree",] > oos["bench",]),
    pct(mean(oos["tree",] > oos["bench",])), "share of splits", "R/50_tree_vs_regression.R")
add("regression_beats_tree_share", mean(oos["nb",] > oos["tree",]),
    pct(mean(oos["nb",] > oos["tree",])), "share of splits", "R/50_tree_vs_regression.R")

seeds <- from_script("A3_seed_stability.R", "res")
sr <- sprintf("%s–%s", f3(min(seeds$model)), f3(max(seeds$model)))
add("model_seed_range", c(min(seeds$model), max(seeds$model)), sr, "Spearman rho range",
    "R/A3_seed_stability.R", sprintf("six seeds x 200 splits; benchmark %s–%s; wins %s–%s",
    f3(min(seeds$benchmark)), f3(max(seeds$benchmark)), pct(min(seeds$win)), pct(max(seeds$win))),
    paste0(nrx(f3(min(seeds$model))), "\\s*(–|-|to|and)\\s*", f3(max(seeds$model))))
add("model_oos_spearman_20_regression", seeds$model[seeds$seed==6093],
    f3(seeds$model[seeds$seed==6093]), "Spearman rho (mean)", "R/20_regression.R / A3 seed 6093",
    "NOT canonical: same model, different splits. Quote only when explaining 20_regression.R output")

## full-sample (in-sample, no split) benchmark comparison, 11_benchmark.R's saved table
bm <- read.csv(file.path(dd, "model_nta_benchmark_20260920.csv"))
add("benchmark_fullsample_spearman", cor(bm$subway_riders, bm$events_311, method="spearman"),
    f3(cor(bm$subway_riders, bm$events_311, method="spearman")), "Spearman rho",
    "R/11_benchmark.R -> model_nta_benchmark_20260920.csv", "all 197, no split; subway ridership",
    nrx(f3(cor(bm$subway_riders, bm$events_311, method="spearman"))))
add("oneliner_unserved_fullsample_spearman", cor(bm$oneliner, bm$events_311, method="spearman"),
    f3(cor(bm$oneliner, bm$events_311, method="spearman")), "Spearman rho",
    "R/11_benchmark.R -> model_nta_benchmark_20260920.csv",
    "ridership at stations with no restroom within 400 m",
    nrx(f3(cor(bm$oneliner, bm$events_311, method="spearman"))))

## =============================================================================
## 2. SHORTLIST, NOISE, POSTERIORS
## =============================================================================
sc <- read.csv(file.path(dd, "model_nta_scored_20260920.csv"))
n15 <- sum(sc$resid_ratio >= 1.5)
add("n_neighbourhoods_modelled", nrow(sc), as.character(nrow(sc)), "NTAs", "R/20_regression.R",
    "residential NTAs (ntatype 0)", paste0(nrx(as.character(nrow(sc))), "(?= (residential |neighbourhoods|NTAs))"))
add("ntas_ratio_ge_1_5", n15, as.character(n15), "NTAs", "R/20_regression.R -> model_nta_scored",
    "observed/predicted >= 1.5", c(paste0(nrx(as.character(n15)), "(?= (neighbourhoods|NTAs|areas|sit at|of the|places))"),
    "(?i)twenty-nine"))
add("max_ratio", max(sc$resid_ratio), sprintf("%.2f", max(sc$resid_ratio)), "ratio",
    "R/20_regression.R", sc$ntaname[which.max(sc$resid_ratio)], nrx(sprintf("%.2f", max(sc$resid_ratio))))
bb <- sc[sc$ntaname=="Brighton Beach",]
add("brighton_beach_expected_ratio", c(expected=bb$pred, ratio=bb$resid_ratio),
    sprintf("%d observed, %.1f expected, %.2f×", bb$events_311, bb$pred, bb$resid_ratio),
    "count / ratio", "R/20_regression.R", sprintf(paste("worked example on the site. Ratio is %.4f: at one decimal it is 3.8×,",
    "NOT 3.9× (3.9 comes from rounding the rounded 3.85). Prefer two decimals"), bb$resid_ratio))
eh <- sc[sc$ntaname=="East Harlem (North)",]
add("east_harlem_ratio", eh$resid_ratio, sprintf("%.2f", eh$resid_ratio), "ratio", "R/20_regression.R",
    sprintf("%d observed, %.1f expected, %d restrooms", eh$events_311, eh$pred, eh$restrooms))

nf <- from_script("A1_noise_floor.R", "list(n15=n15, mx=mx, obs_max=max(d$events_311/pmax(mu,.01)))")
add("null_nb_mean_ntas_ge_1_5", mean(nf$n15), sprintf("%.1f", mean(nf$n15)), "NTAs (mean of 500 sims)",
    "R/A1_noise_floor.R", "NB null (areas do differ by the estimated spread)", nrx(sprintf("%.1f", mean(nf$n15))))

eb <- from_script("A6_empirical_bayes.R",
  "list(name=d$ntaname, p=p15, loo=res$P_LOO, loo_name=res$neighbourhood)")
o <- order(-eb$p); hi <- o[eb$p[o] > 0.95]
add("posterior_gt_0_95_n", length(hi), as.character(length(hi)), "NTAs", "R/A6_empirical_bayes.R",
    paste("P(true relative risk > 1.5) > 0.95:", paste(eb$name[hi], collapse="; ")),
    c(paste0("(?i)\\b(", c("one","two","three","four","five","six","seven","eight","nine")[length(hi)],
             "|", length(hi), ") neighbourhoods (are |clear|individually|above)")))
add("posterior_gt_0_95_names", eb$name[hi], paste(eb$name[hi], collapse="; "), "names",
    "R/A6_empirical_bayes.R", "ordered by posterior probability")
nm <- o[length(hi)+1]
add("posterior_near_miss", c(name=eb$name[nm], p=round(eb$p[nm],3)),
    sprintf("%s %.3f", eb$name[nm], eb$p[nm]), "posterior probability", "R/A6_empirical_bayes.R",
    "first area below 0.95", nrx(sprintf("%.3f", eb$p[nm])))
add("posterior_loo_survivors", sum(eb$loo > 0.95), sprintf("%d of %d", sum(eb$loo > 0.95), length(eb$loo)),
    "NTAs", "R/A6_empirical_bayes.R", "top 7 re-scored leave-one-out (model and prior refit)")

## =============================================================================
## 3. SUPPLY: register counts, hours (logic of R/80_corrections.R §4)
## =============================================================================
rr <- read.csv(file.path(dd, "nycrestrooms_i7jb-7jku_20260920.csv"), stringsAsFactors=FALSE)
op <- rr$status=="Operational"; opy <- op & rr$open=="Year Round"
add("restrooms_register_total", nrow(rr), comma(nrow(rr)), "facilities", "data_raw/nycrestrooms_i7jb-7jku",
    "all rows on the register", nrx(comma(nrow(rr))))
add("restrooms_operational", sum(op), comma(sum(op)), "facilities", "data_raw/nycrestrooms_i7jb-7jku",
    "status == Operational. The Council dashboard's 973 is an EXTERNAL figure (see external)", nrx(comma(sum(op))))
add("restrooms_operational_year_round", sum(opy), comma(sum(opy)), "facilities",
    "data_raw/nycrestrooms_i7jb-7jku", "Operational & open == Year Round", nrx(comma(sum(opy))))
add("restrooms_operational_seasonal", sum(op) - sum(opy), comma(sum(op)-sum(opy)), "facilities",
    "data_raw/nycrestrooms_i7jb-7jku", "operational but seasonal", nrx(comma(sum(op)-sum(opy))))
add("restrooms_not_operational", nrow(rr) - sum(op), comma(nrow(rr)-sum(op)), "facilities",
    "data_raw/nycrestrooms_i7jb-7jku", "register minus operational")
boiler <- grepl("Open later seasonally", rr$hours_of_operation, ignore.case=TRUE)
add("hours_placeholder_year_round", sum(opy & boiler), comma(sum(opy & boiler)), "facilities",
    "R/80_corrections.R §3", sprintf("%s of year-round operational carry the placeholder string",
    pct(mean(boiler[opy]), 1)), nrx(comma(sum(opy & boiler))))
add("hours_genuine_year_round", sum(opy & !boiler), comma(sum(opy & !boiler)), "facilities",
    "R/80_corrections.R §3", paste("year-round operational with real hours. NB outputs/hub_open_access.json",
    "reports 316 'parsed_explicit' on a different base (all 975 operational, placeholder AND unparseable excluded)"))
ph <- read.csv(file.path(dd, "parsed_hours_20260920.csv"))
sel <- ph$parsed & ph$is_open & ph$facility_id %in% which(opy)
f24 <- unique(ph$facility_id[which(sel & (ph$close_hour - ph$open_hour) >= 24)])
add("open_24h", length(f24), as.character(length(f24)), "facilities", "R/80_corrections.R §4",
    paste("our register, derived. The earlier published 9 counted an NA; the Council dashboard's",
    "'8 open 24/7' is an external figure that happens to agree"),
    c("(?i)\\b(8|eight) facilities[^.]{0,30}24", "(?i)\\*\\*8\\*\\*[^.]{0,30}24"))
sat <- ph |> filter(day_of_week==7, parsed, is_open, facility_id %in% which(opy))
add("open_after_11pm_saturday", sum(sat$close_hour > 23), as.character(sum(sat$close_hour > 23)),
    "facilities", "R/80_corrections.R §4",
    sprintf("close after 23:00 on Saturday (day 7). %d close at or after 23:00; earlier published 21",
            sum(sat$close_hour >= 23)))

## =============================================================================
## 4. OUTCOME CLEANING (East Harlem dedup, top-1%, the funnel)
## =============================================================================
ev <- read.csv(file.path(dd, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"), stringsAsFactors=FALSE)
u  <- ev[ev$complaint_type=="Urinating in Public",]
pu <- u[u$location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),]
pu$ym <- substr(pu$created_date, 1, 7)
## coords filter FIRST, then one per address-month (the modelled series; the reverse
## order gives 3,625 and is not what the pipeline uses)
pc  <- pu[is.finite(suppressWarnings(as.numeric(pu$latitude))),]
dd2 <- pc[!duplicated(pc[,c("incident_address","ym")]),]
add("outcome_raw_urination", nrow(u), comma(nrow(u)), "complaints", "data_raw/nyc311_urination_*",
    "Urinating in Public, 2020-2026", nrx(comma(nrow(u))))
add("outcome_public_places", nrow(pu), comma(nrow(pu)), "complaints", "notes/outcome_count_reconciliation.md",
    "public location types", nrx(comma(nrow(pu))))
add("outcome_dedup_coords", nrow(dd2), comma(nrow(dd2)), "complaints", "notes/outcome_count_reconciliation.md",
    "one per address-month, coords required (citywide)", nrx(comma(nrow(dd2))))
add("outcome_modelled", sum(sc$events_311), comma(sum(sc$events_311)), "complaints",
    "R/20_regression.R", "inside the 197 residential NTAs", nrx(comma(sum(sc$events_311))))
ta <- sort(table(pu$incident_address[nzchar(pu$incident_address)]), decreasing=TRUE)
k  <- ceiling(0.01*length(ta)); top1 <- sum(ta[1:k])/nrow(pu)
add("top1pct_address_share", top1, pct(top1, 1), "share of complaints", "data_raw/nyc311_urination_*",
    sprintf("top %d of %s addresses (ceiling of 1%%), public-place complaints before dedup", k, comma(length(ta))),
    nrx(pct(top1, 1)))
ehc <- pu[pu$community_board=="11 MANHATTAN",]
t5  <- sort(table(ehc$incident_address), decreasing=TRUE)[1:5]
add("east_harlem_dedup", c(top5=sum(t5), total=nrow(ehc)), sprintf("%d of %d", sum(t5), nrow(ehc)),
    "complaints", "data_raw/nyc311_urination_*",
    paste("community board 11 Manhattan, raw public-place counts; five addresses:",
          paste(names(t5), collapse=" | ")), paste0(sum(t5), " of (its )?", nrow(ehc)))

## =============================================================================
## 5. CONDITION (Parks inspections)
## =============================================================================
a8 <- from_script("A8_condition_trend.R", paste0(
  "list(fr = w[cs_overall_condition %in% c('A','U'), .(f=mean(cs_overall_condition=='U')), by=yr][order(yr)],",
  " acc = w[, .(a=mean(cs_overall_condition=='A')), by=yr][order(yr)],",
  " fe = ct['yrf2026', c(1,2,4)], n_insp = nrow(d))"))
fr <- setNames(a8$fr$f, a8$fr$yr); ac <- setNames(a8$acc$a, a8$acc$yr)
add("parks_fail_2024", fr[["2024"]], pct(fr[["2024"]], 1), "share of rated inspections",
    "R/A8_condition_trend.R", "Jan-Jun matched window", nrx(pct(fr[["2024"]], 1)))
add("parks_fail_2026", fr[["2026"]], pct(fr[["2026"]], 1), "share of rated inspections",
    "R/A8_condition_trend.R", "Jan-Jun matched window (data end 28 Jun 2026)", nrx(pct(fr[["2026"]], 1)))
add("parks_fail_fe_2026_vs_2024", a8$fe[[1]], sprintf("+%.1f pp", 100*a8$fe[[1]]), "percentage points",
    "R/A8_condition_trend.R", sprintf("facility fixed effects, SE %.1f pp clustered by facility, p = %.1e",
    100*a8$fe[[2]], a8$fe[[3]]), nrx(sprintf("%.1f", 100*a8$fe[[1]])))
add("parks_acceptable_2024_2026", c(ac[["2024"]], ac[["2026"]]),
    sprintf("%s -> %s", pct(ac[["2024"]],1), pct(ac[["2026"]],1)), "share of all inspections",
    "R/A8_condition_trend.R", "open AND acceptable")
add("parks_inspections_n", a8$n_insp, comma(a8$n_insp), "inspections", "R/A8_condition_trend.R", "",
    nrx(comma(a8$n_insp)))

## =============================================================================
## 6. COSTS
## =============================================================================
a7 <- from_script("A7_repair_vs_build.R", "list(nb=nb, rc=rc, cp=cp, t=table(ct$type[!is.na(ct$cost)]))")
add("build_new_median", a7$nb, usdM(a7$nb), "USD", "R/A7_repair_vs_build.R",
    sprintf("n=%d capital-tracker projects; also shown as $%s", a7$t[["Build new"]], comma(a7$nb)),
    c(nrx(usdM(a7$nb)), nrx(paste0("$", comma(a7$nb)))))
add("reconstruct_median", a7$rc, usdM(a7$rc, 2), "USD", "R/A7_repair_vs_build.R",
    sprintf("n=%d; also $%s", a7$t[["Reconstruct existing"]], comma(a7$rc)),
    c(nrx(usdM(a7$rc, 2)), nrx(paste0("$", comma(a7$rc)))))
add("component_median", a7$cp, paste0("$", comma(a7$cp)), "USD", "R/A7_repair_vs_build.R",
    sprintf("n=%d only — too thin to price a programme", a7$t[["Component work (roof/plumbing/electrical)"]]))
a2 <- from_script("A2_cost_bands.R", "median(v, na.rm=TRUE)")
add("pooled_project_median", a2, paste0("$", comma(a2)), "USD", "R/A2_cost_bands.R",
    "all 191 restroom projects, banded rows valued at band midpoint", c(nrx(paste0("$", comma(a2))), nrx(usdM(a2, 2))))

iv <- read.csv(file.path(dd, "model_nta_interventions_20260920.csv"))
sh <- iv[iv$resid_ratio >= 1.5,]
tot <- sum(sh$capex, na.rm=TRUE)
add("programme_capex_total", tot, usdM(tot), "USD", "R/60_cost_layer.R -> model_nta_interventions",
    "cheapest fix per shortlisted NTA; hours counted as $0 CAPITAL (see hours_extension_*)", nrx(usdM(tot)))
mix <- table(sh$intervention)
add("intervention_mix", as.list(mix), paste(sprintf("%s %d", names(mix), as.integer(mix)), collapse="; "),
    "NTAs", "R/60_cost_layer.R")
CAPmod <- from_code("60_cost_layer.R", "modular")
add("unit_in_all_shortlist", nrow(sh)*CAPmod, usdM(nrow(sh)*CAPmod), "USD", "R/60_cost_layer.R",
    sprintf("%d x $%s modular — $1.2M = NYC Parks pilot budget per unit (see modular_unit_cost_in_code)", nrow(sh), comma(CAPmod)),
    nrx(usdM(nrow(sh)*CAPmod)))
add("modular_unit_cost_in_code", CAPmod, usdM(CAPmod), "USD", "R/60_cost_layer.R, R/61_cost_annualised.R",
    paste("SOURCED 2026-09-23: NYC Parks' $6M five-unit Portland Loo pilot = $1.2M/unit budgeted",
          "(reported outturn ~$1.0M/site: $185k unit + ~$815k utilities/site work). See external.modular_portland_loo.",
          "Compare modular_pilot_implied_per_unit_year (service contract, not capital)"))

## 2026-09-23 fix: annualised shortlist total (61), now that reconstruction is priced correctly
sc61 <- read.csv(file.path(dd, "model_shortlist_costed_20260920.csv"))
ann61 <- sum(sc61$annual_cost, na.rm=TRUE)
add("shortlist_annual_cost_total", ann61, usdM(ann61, 2), "USD per year", "R/61_cost_annualised.R -> model_shortlist_costed",
    "modular + reconstruction annualised over 20 yr at the central rate; hours at the labelled wage assumption", nrx(usdM(ann61, 2)))

## discount rate(s) actually in code
## 2026-09-23 fix: central rate harmonised to 3% in 61, 94 and A2; the break-even rate is now
## parsed from 94's crf() call instead of typed here.
d61 <- from_code("61_cost_annualised.R", "DISC")
add("discount_rate_programme", d61, pct(d61), "rate", "R/61_cost_annualised.R",
    "central rate used everywhere (61 shortlist costing, 94 break-even, A2 corrected median); sensitivity 2%/5% in 94")
l94 <- grep("^A <- crf\\(MED,20,", readLines("R/94_breakeven.R"), value=TRUE)
stopifnot(length(l94)==1)
d94 <- as.numeric(sub("^A <- crf\\(MED,20,([0-9.]+)\\).*", "\\1", l94))
add("discount_rate_breakeven", d94, pct(d94, if (d94*100 %% 1) 1 else 0), "rate", "R/94_breakeven.R (A <- crf(MED,20,r))",
    "central break-even rate; must equal discount_rate_programme")
stopifnot(isTRUE(all.equal(d94, d61)))
crf <- function(p,n,r) p*(r*(1+r)^n)/((1+r)^n-1)
be <- from_script("94_breakeven.R", "A")
add("breakeven_annual_cost", be, paste0("$", comma(be)), "USD per year", "R/94_breakeven.R",
    sprintf("numeric-only median project, 20 yr @ %s", pct(d94)), nrx(paste0("$", comma(be))))
a2ann <- crf(a2, 20, d61)
add("pooled_median_annualised", a2ann, paste0("$", comma(a2ann)), "USD per year", "R/A2_cost_bands.R",
    sprintf("pooled_project_median over 20 yr @ %s", pct(d61)), nrx(paste0("$", comma(a2ann))))
add("pooled_cost_per_use_200day", a2ann/73000, sprintf("$%.2f", a2ann/73000), "USD per use",
    "derived here from pooled_median_annualised", "at 200 uses/day = 73,000/yr (94's per-use grid)",
    paste0(nrx(sprintf("$%.2f", a2ann/73000)), "(?= per use)"))

## ---- hours extension, priced honestly ---------------------------------------
WAGE <- from_code("61_cost_annualised.R", "WAGE"); XH <- from_code("61_cost_annualised.R", "EXTRA_H")
c1 <- from_script("C1_trial_power.R",
  "list(n_areas=nrow(hrs), n_fac=sum(hrs$restrooms), sm=sm, n_treat=n_treat, z=z, phone=phone, base_yr=base_yr)")
ann <- c1$n_fac * XH * 365 * WAGE
pv10 <- ann * (1 - (1+d61)^-10)/d61
add("hours_extension_areas", c1$n_areas, as.character(c1$n_areas), "NTAs", "R/C1_trial_power.R",
    "shortlisted areas whose fix is 'Extend operating hours'")
add("hours_extension_facilities", c1$n_fac, as.character(c1$n_fac), "facilities", "R/C1_trial_power.R",
    "restrooms inside those areas (post geography fix; the site's 44 came from a stale investment table)",
    paste0(nrx(as.character(c1$n_fac)), "(?= facilities)"))
add("hours_extension_annual", ann, usdM(ann), "USD per year", "R/C1_trial_power.R / R/61_cost_annualised.R",
    sprintf("%d facilities x %g h x 365 x $%g/h (wage and hours are labelled ASSUMPTIONS in 61). The site shows hours as $0 CAPITAL; this is the recurring cost",
            c1$n_fac, XH, WAGE), nrx(usdM(ann)))
add("hours_extension_trial_10mo", ann*10/12, usdM(ann*10/12), "USD", "R/C1_trial_power.R", "10-month staggered trial",
    nrx(usdM(ann*10/12)))
add("hours_extension_10yr_undiscounted", ann*10, usdM(ann*10), "USD", "derived here from hours_extension_annual",
    "10 years, no discounting")
add("hours_extension_10yr_pv", pv10, usdM(pv10), "USD", "derived here from hours_extension_annual",
    sprintf("present value, 10 years at %s (61's rate)", pct(d61)))
mde <- exp(c1$z*sqrt(2/c1$n_treat)) - 1
add("trial_mde_summons", mde, pct(mde), "smallest detectable change", "R/C1_trial_power.R",
    sprintf("%s deduped summonses over 3.5 yr in the trial areas, 80%% power, 5%% two-sided", comma(c1$sm)),
    paste0(nrx(pct(mde)), "(?! (fewer|of))"))
mde311 <- function(r) { n <- r*10/12/2; exp(c1$z*sqrt(2/n)) - 1 }
add("trial_mde_311_all", mde311(c1$base_yr), pct(mde311(c1$base_yr)), "smallest detectable change",
    "R/C1_trial_power.R", "311, all channels", nrx(pct(mde311(c1$base_yr))))
add("trial_mde_311_phone", mde311(c1$base_yr*c1$phone), pct(mde311(c1$base_yr*c1$phone)),
    "smallest detectable change", "R/C1_trial_power.R", "311, phone only", nrx(pct(mde311(c1$base_yr*c1$phone))))

## =============================================================================
## 7. EXTERNAL FACTS (the only typed constants) — each with a source URL
## =============================================================================
EXT <- list(
  ll58_target = list(value=2120, display="2,120", unit="restrooms by 2035",
    source="https://intro.nyc/local-laws/2025-58", note="Local Law 58 of 2025; at least half publicly owned"),
  ll58_enacted = list(value="2025-05-12", display="May 2025", unit="date",
    source="https://intro.nyc/local-laws/2025-58", note="passed 10 Apr 2025, returned unsigned 12 May 2025. NOT July 2025 (that is LL92)"),
  ll58_strategy_due = list(value="2026-11-01", display="1 Nov 2026", unit="date",
    source="https://pix11.com/news/local-news/deadline-delayed-for-plan-to-expand-nyc-public-bathrooms/",
    note="originally due 1 Sep 2026; deputy mayor's letter Aug 2026"),
  council_dashboard_operational = list(value=973, display="973", unit="facilities",
    source="https://council.nyc.gov/data/public-restroom-analysis/", note="Council dashboard (Dec 2025). Our register says 975"),
  council_dashboard_24h = list(value=8, display="8", unit="facilities open 24/7",
    source="https://council.nyc.gov/data/public-restroom-analysis/", note="agrees with our derived open_24h"),
  council_dashboard_5min_walk = list(value=0.4942, display="49.42%", unit="share of residents",
    source="https://council.nyc.gov/data/public-restroom-analysis/",
    note="method undisclosed; our 53.45% (R/31) is NOT comparable (WORKLOG: comparison withdrawn). Cite only with that caveat"),
  council_audit_closed = list(value=c(36,337), display="36 of 337", unit="rooms closed in posted hours",
    source="https://council.nyc.gov/press/wp-content/uploads/sites/56/2025/12/OID_Restrooms-REPORT_121625-v4.pdf",
    note="Council OID 'Good to Go?' audit, Aug-Sep 2025, stratified random; all 36 in parks"),
  council_audit_missing_necessity = list(value=c(129,301), display="129 of 301", unit="open rooms missing a basic necessity",
    source="https://council.nyc.gov/press/wp-content/uploads/sites/56/2025/12/OID_Restrooms-REPORT_121625-v4.pdf", note=""),
  # 2026-09-23 site-merge: hours_per_day and the site list added (verified against the release 23 Sep)
  pilot = list(value=list(units=17, cost=4e6, years=1, hours="7am-10pm", hours_per_day=15, sites_published="2026-09-16",
      sites_midtown=0, sites_astoria_woodside=4),
    display="17 units, $4M, one year, 7am–10pm", unit="",
    source="https://www.nyc.gov/mayors-office/news/2026/09/mayor-mamdani-brings-17-new-public-bathrooms-to-neighborhoods-ac",
    note=paste("Throne Labs via NYCEDC; self-contained units, no hookups; operator cleans and maintains (service contract).",
      "Queens sites: Astoria Blvd S & 31 St, Northern Blvd & 31 St, Northern Blvd & 54 St, 34 Ave & 64 St (Astoria/Woodside);",
      "Manhattan: Cooper Sq, Malcolm X Plaza, Delancey & Suffolk, Plaza Alianza Dominicana — none in Midtown")),
  ## ---- 2026-09-23 site-merge: external facts added for the rewritten site ----
  ll114 = list(value="2022-11-28", display="Local Law 114 of 2022", unit="law",
    source="https://intro.nyc/local-laws/2022-114",
    note="report identifying at least one feasible bathroom location per ZIP code area; no funding attached"),
  ll92 = list(value="2025-07", display="Local Law 92 of 2025", unit="law",
    source="https://council.nyc.gov/press/2025/07/12/2922/",
    note="each bathroom strategy report must update all active/planned capital projects at the LL114 sites"),
  amato_2022 = list(value=list(change_per_week=-12.47, p=0.0002, installations=13), display="-12.47 reports/week (p = 0.0002)",
    unit="311 feces reports per week within 500 m", source="https://pmc.ncbi.nlm.nih.gov/articles/PMC9441075/",
    note="Amato et al., BMC Public Health 2022; San Francisco Pit Stop, 13 new-restroom installations, 2014-2020; not NYC"),
  privy_by_the_bay_2025 = list(value="effect appears to be small", display="'the effect appears to be small'", unit="quote",
    source="https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0327795",
    note="PLOS ONE, 14 Aug 2025, SF 311 waste reports 2009-2022; qualifies Amato 2022"),
  restroom_register_last_updated = list(value="2025-06-27", display="27 June 2025", unit="date",
    source="https://data.cityofnewyork.us/d/i7jb-7jku", note="rowsUpdatedAt of the register; the catalogue claims Nov 2025"),
  peer_cities = list(value=list(
      san_francisco="https://sfpublicworks.org/pitstop",
      washington_dc="https://dcpublicrestrooms.org/wp-content/uploads/2023/12/Public-Restroom-Pilot-Program.pdf",
      paris="https://opendata.paris.fr/explore/dataset/sanisettesparis/",
      tokyo="https://tokyotoilet.jp/en/maintenance/",
      london="https://www.cityoflondon.gov.uk/services/streets/clean-streets/public-toilets"),
    display="SF, DC, Paris, Tokyo, London", unit="links",
    source="see value", note="each link opened 23 Sep 2026 (DC pilot statute: monthly reports on use by date/time and misuse)"),
  modular_portland_loo = list(value=list(pilot_budget=6e6, units=5, per_unit_budget=1.2e6,
      per_site_reported=1e6, unit_only=185000), display="$6M for 5 units = $1.2M each", unit="",
    source="https://www.nyc.gov/mayors-office/news/2025/07/mayor-adams-nyc-parks-commissioner-rodriguez-rosa-continue-we-outside-summer-announcing",
    note=paste("2026-09-23: NYC Mayor's Office / Parks, 1 Jul 2025: '$6 million pilot' for five Portland Loos, 'constructed for",
      "only $1 million per location, plus some additional site-specific costs'; traditional build 'at least $3.5 million'.",
      "Unit alone ~$185k, ~$815k utilities/site work (amNY, https://www.amny.com/news/modular-restrooms-nyc-parks-million-install/).",
      "Our $1.2M = pilot budget per unit; outturn ~$1.0M+ is the low case")),
  ddc_build = list(value=list(cost=19.3e6, buildings=5), display="$19.3M for 5 buildings", unit="",
    source="https://www.nyc.gov/site/ddc/about/press-releases/2026/pr-062626-MurphyBros.page",
    note="announced 26 Jun 2026; independent check on build_new_median")
)

## ---- derived FROM external facts (arithmetic only) ----------------------------
gap <- EXT$ll58_target$value - sum(op)
add("ll58_gap", gap, comma(gap), "facilities", "external ll58_target - restrooms_operational",
    sprintf("%s - %s. Using the Council's 973 gives %s — do not mix", comma(EXT$ll58_target$value),
            comma(sum(op)), comma(EXT$ll58_target$value - 973)), nrx(comma(gap)))
pilot_unit <- EXT$pilot$value$cost / EXT$pilot$value$units / EXT$pilot$value$years
add("modular_pilot_implied_per_unit_year", pilot_unit, sprintf("$%sk", comma(pilot_unit/1e3)),
    "USD per unit-year", "external pilot", paste("$4M / 17 units / 1 year. A SERVICE CONTRACT (units + cleaning +",
    "maintenance), not capital — not directly comparable with the $1.2M capital assumption"))
add("ddc_per_building", 19.3e6/5, usdM(19.3e6/5, 2), "USD", "external ddc_build", "corroborates build_new_median")
acs <- read.csv(file.path(dd, "census_acs5_2024_tract_demographics_20260920.csv"), colClasses=c(geoid="character"))
pop <- sum(acs$pop_total, na.rm=TRUE)
add("nyc_population_acs", pop, comma(pop), "residents", "data_raw/census_acs5_2024_tract", "ACS 5-yr 2024, sum of tracts")
add("restrooms_per_100k_now", sum(op)/pop*1e5, sprintf("%.1f", sum(op)/pop*1e5), "per 100k residents",
    "restrooms_operational / nyc_population_acs")
add("restrooms_per_100k_target", EXT$ll58_target$value/pop*1e5, sprintf("%.1f", EXT$ll58_target$value/pop*1e5),
    "per 100k residents", "external ll58_target / nyc_population_acs", "at today's population")

## =============================================================================
## 8. HUB x HOURS (outputs/hub_open_access.json, from R/C2_hub_open_access.R) — merged if present
## =============================================================================
hub <- NULL; hf <- "outputs/hub_open_access.json"
if (file.exists(hf)) {
  hub <- fromJSON(hf, simplifyVector=FALSE)
  hub$built <- NULL                       # keep this file free of dates
  W <- hub$headline$off_season$Wednesday
  for (h in c("14:00","18:00","21:00")) {
    k <- sub(":00", "", h)
    add(paste0("hub_top50_walk_min_wed_", k), W[[h]]$top50_entry_weighted_walk_min,
        sprintf("%.1f min", W[[h]]$top50_entry_weighted_walk_min), "minutes (straight line, lower bound)",
        "R/C2_hub_open_access.R", paste("top-50 hubs, entry-weighted, Wednesday, off-season placeholder close 16:00;",
        W[[h]]$top50_hubs_none_within_500m, "of 50 with none open within 500 m"))
  }
}

## =============================================================================
## 9. 2026-09-23 site-merge: every other number the rewritten site quotes
## Each one is read from data_raw/ or evaluated inside the script that owns it.
## =============================================================================
## ---- pilot arithmetic (external inputs only) ----
pv <- EXT$pilot$value
add("pilot_cost_per_planned_open_hour", pv$cost/(pv$units*pv$hours_per_day*365*pv$years),
    sprintf("$%.2f", pv$cost/(pv$units*pv$hours_per_day*365*pv$years)), "USD per planned unit-open hour",
    "external pilot", "$4M / (17 units x 15 h x 365). PLANNED hours: the metric we recommend divides by VERIFIED open hours")

## ---- cost logic after the 23 Sep repricing (61) ----
csd <- read.csv(file.path(dd, "model_shortlist_costed_20260920.csv"))
csd <- csd[order(csd$per_excess),]
add("cheapest_per_excess_first", c(name=csd$ntaname[1], action=csd$intervention[1], per_excess=round(csd$per_excess[1])),
    sprintf("%s, %s, $%s per excess complaint a year", csd$ntaname[1], csd$intervention[1], comma(csd$per_excess[1])),
    "USD per excess complaint per year", "R/61_cost_annualised.R -> model_shortlist_costed",
    "lowest annual cost per excess complaint in the shortlist")
add("first_repair_rank", which(csd$intervention=="Reconstruct or repair")[1],
    as.character(which(csd$intervention=="Reconstruct or repair")[1]), "rank", "R/61_cost_annualised.R",
    "rank of the first reconstruction in cost per excess complaint")
add("hours_cost_per_area_year", XH*365*WAGE, paste0("$", comma(XH*365*WAGE)), "USD per year",
    "R/61_cost_annualised.R (cost_of)", "61 prices 'extend hours' as ONE extra attendant per AREA, not per restroom")
## sensitivity: price hours per RESTROOM in the area (as C1 does for the trial) and re-rank
alt <- csd; ih <- alt$intervention=="Extend operating hours"
alt$annual_cost[ih] <- alt$annual_cost[ih] * pmax(alt$restrooms[ih], 1)
alt$per_excess <- alt$annual_cost/alt$excess; alt <- alt[order(alt$per_excess),]
add("cheapest_per_excess_if_hours_per_restroom", c(name=alt$ntaname[1], action=alt$intervention[1], per_excess=round(alt$per_excess[1])),
    sprintf("%s, %s, $%s per excess complaint a year", alt$ntaname[1], alt$intervention[1], comma(alt$per_excess[1])),
    "USD per excess complaint per year", "derived here from model_shortlist_costed",
    sprintf("hours priced per restroom; East Harlem (North) then ranks %d", which(alt$ntaname=="East Harlem (North)")))
add("east_harlem_rank_if_hours_per_restroom", which(alt$ntaname=="East Harlem (North)"),
    as.character(which(alt$ntaname=="East Harlem (North)")), "rank", "derived here from model_shortlist_costed")
wf <- from_script("61_cost_annualised.R", "w_flip")
add("hours_flip_wage", wf, paste0("$", wf, "/h"), "USD per staffed hour", "R/61_cost_annualised.R (w_flip)",
    "hourly staffing cost at which extending hours stops being the cheapest option (searched in $5 steps)")
add("hours_wage_assumption", WAGE, paste0("$", WAGE, "/h"), "USD per staffed hour", "R/61_cost_annualised.R (WAGE)", "ASSUMPTION, loaded attendant wage")
add("hours_extra_per_day", XH, as.character(XH), "hours/day", "R/61_cost_annualised.R (EXTRA_H)", "ASSUMPTION")

## ---- repair backlog, capital-delivery time (register data) ----
pr <- read.csv(file.path(dd, "pipRestrooms_9byw-znpj_20260920.csv"), stringsAsFactors=FALSE)
add("pip_long_term_closed", c(closed=sum(pr$long_term_closure=="Yes"), repairs=sum(pr$reason_closed=="Repairs"), of=nrow(pr)),
    sprintf("%d of %d (%d for repairs)", sum(pr$long_term_closure=="Yes"), nrow(pr), sum(pr$reason_closed=="Repairs")),
    "comfort stations", "data_raw/pipRestrooms_9byw-znpj", "PIP long-term closure flag (undated, current state)")
dur <- from_script("A7_repair_vs_build.R", paste0("{ s <- as.Date(substr(ct$designstart,1,10)); f <- as.Date(substr(ct$constructionactualcompletion,1,10));",
  " y <- as.numeric(f - s)/365.25; y <- y[is.finite(y) & y > 0]; c(median=median(y), n=length(y)) }"))
add("capital_median_years", dur[["median"]], sprintf("%.1f years", dur[["median"]]), "years design start -> construction complete",
    "R/A7_repair_vs_build.R (ct)", sprintf("median over %d completed restroom projects in the capital tracker", dur[["n"]]))
parks_n <- sum(rr$location_type=="Park")
add("restrooms_in_parks", parks_n, sprintf("%s of %s", comma(parks_n), comma(nrow(rr))), "facilities",
    "data_raw/nycrestrooms_i7jb-7jku", "location_type == Park, all statuses")
f24n <- rr$facility_name[f24]
add("open_24h_names", f24n, paste(f24n, collapse="; "), "names", "R/80_corrections.R §4 logic",
    "the 8 '24-hour' facilities — parkway gas stations and a snack bar, not walk-in public toilets")

## ---- time of day: complaint timing (70) and area coverage (B1) ----
tod <- from_script("70_audit_checks.R", "list(h=as.numeric(h), n=nrow(e))")
names(tod$h) <- 0:23
add("complaints_peak_hour", as.integer(names(which.max(tod$h))), sprintf("%02d:00", as.integer(names(which.max(tod$h)))),
    "hour of day", "R/70_audit_checks.R", "de-duplicated series; 311 filing time")
add("complaints_evening_share", sum(tod$h[as.character(18:23)])/tod$n, pct(sum(tod$h[as.character(18:23)])/tod$n),
    "share filed 18:00-23:59", "R/70_audit_checks.R", "de-duplicated series")
cov <- from_script("B1_small_maps.R", "c(c3=mean(c3), c9=mean(c9))")
add("coverage_3pm", cov[["c3"]]/100, sprintf("%.0f%%", cov[["c3"]]), "mean share of NTA land within 5 min of an open restroom",
    "R/B1_small_maps.R", "genuine-hours facilities only (placeholder hours excluded)")
add("coverage_9pm", cov[["c9"]]/100, sprintf("%.1f%%", cov[["c9"]]), "mean share of NTA land within 5 min of an open restroom",
    "R/B1_small_maps.R", "genuine-hours facilities only (placeholder hours excluded)")

## ---- reporting bias (A4, 70) and the rejected summons outcome (91) ----
a4 <- from_script("A4_reporting_channel.R", "cor(per$events, per$online)")
add("channel_online_cor", a4, sprintf("%.2f", a4), "Pearson r across community boards", "R/A4_reporting_channel.R",
    "de-duplicated complaints vs share filed online")
ph70 <- from_script("70_audit_checks.R", "as.data.frame(rk[, c('ntaname','rank_all','rank_phone')])")
prk <- function(n) ph70$rank_phone[ph70$ntaname==n]
ord <- function(i) paste0(i, ifelse(i %% 100 %in% 11:13, "th", c("th","st","nd","rd",rep("th",6))[i %% 10 + 1]))
PHN <- c(east_harlem="East Harlem (North)", astoria="Astoria (East)-Woodside (North)", williamsbridge="Williamsbridge-Olinville")
for (k in names(PHN)) add(paste0("phone_rank_", k), prk(PHN[[k]]), ord(prk(PHN[[k]])),
      "rank of 197 on phone-only reports", "R/70_audit_checks.R", PHN[[k]])
sa <- from_script("91_rebuild_outcome.R", "cor(d$summons, d$alcohol, method='spearman')")
add("summons_alcohol_cor", sa, sprintf("%.2f", sa), "Spearman across NTAs", "R/91_rebuild_outcome.R",
    "urination summonses vs alcohol summonses: tracks enforcement")

## ---- winterization DiD (93): main effect and the placebo ----
wz <- from_script("93_winterization.R", paste0("sapply(c('urin','alco'), function(v) {",
  " m <- glm(as.formula(paste0(v, ' ~ winter*seasonal + fid + offset(log(nm))')), family=poisson, data=cs);",
  " exp(coef(m)[['winter:seasonal']]) })"))
add("winter_irr_main", wz[["urin"]], sprintf("%.3f", wz[["urin"]]), "IRR", "R/93_winterization.R", "urination summonses, seasonal x winter")
add("winter_irr_placebo", wz[["alco"]], sprintf("%.3f", wz[["alco"]]), "IRR", "R/93_winterization.R", "alcohol summonses (placebo)")

## ---- deterioration: within-inspector placebo (A8) ----
wi <- from_script("A8_condition_trend.R", paste0("sapply(c('cs_litter','cs_structural'), function(cc) {",
  " s <- d7[inspector %in% b7 & yr %in% c(2024,2026) & get(cc) %in% c('A','U'), .(f=mean(get(cc)=='U')), by=yr][order(yr)];",
  " c(s$f, length(b7)) })"))
add("inspectors_both_years", wi[3,1], as.character(wi[3,1]), "inspectors", "R/A8_condition_trend.R", "rated comfort stations in both 2024 and 2026")
add("inspector_litter_2024_2026", wi[1:2,1], sprintf("%.3f -> %.3f", wi[1,1], wi[2,1]), "fail share", "R/A8_condition_trend.R", "same seven inspectors")
add("inspector_structural_2024_2026", wi[1:2,2], sprintf("%.3f -> %.3f", wi[1,2], wi[2,2]), "fail share", "R/A8_condition_trend.R", "same seven inspectors")

## ---- robustness (96) and per-area posteriors (A6) ----
cs96 <- from_script("96_commercial_supply.R", "cor(d$r0, d$r1, method='spearman')")
add("commercial_supply_rank_cor", cs96, sprintf("%.3f", cs96), "Spearman", "R/96_commercial_supply.R", "ranking with vs without 1,886 chain outlets")
add("posterior_top_values", setNames(round(eb$p[hi], 4), eb$name[hi]),
    paste(sprintf("%s %s", eb$name[hi], ifelse(eb$p[hi] > 0.999, ">0.999", sprintf("%.3f", eb$p[hi]))), collapse="; "),
    "posterior probability", "R/A6_empirical_bayes.R", "P(true relative risk > 1.5)")

## ---- dataset row counts (Data & code tab) and script count ----
rows_of <- function(f) nrow(data.table::fread(file.path(dd, f), showProgress=FALSE, select=1L))
DS <- c(restrooms="nycrestrooms_i7jb-7jku_20260920.csv", urination311="nyc311_urination_publictoilet_erm2-nwe9_20260920.csv",
  dirty311="nyc311_dirtycondition_erm2-nwe9_20260920.csv", oath_urination="nypd_oath_urination_hxbk-grd3_20260920.csv",
  oath_alcohol="nypd_oath_alcohol_placebo_hxbk-grd3_20260920.csv", acs_tracts="census_acs5_2024_tract_demographics_20260920.csv",
  lodes="census_lodes8_nywac2023_20260920.csv", tlc="tlc_c5iv-bn4s_zonemonth_20260920.csv", mta_monthly="mta_ak4z-sape_monthly_20260920.csv",
  mta_stations="mta_39hk-dx4f_stations_20260920.csv", hotels="nyc_tjus-cn27_hotels_20260920.csv", parks="parksprops_enfh-gkve_20260920.csv",
  capital="capitaltracker_4hcv-tc5r_20260920.csv", pip_master="pipInspectionsMaster_yg3y-7juh_20260920.csv",
  pip_sites="pipAllSites_buk3-3qpr_20260920.csv", park_structures="parkstructures_n8q6-i44s_20260920.csv",
  covid_closures="csclosurecovid_i5n2-q8ck_20260920.csv", taxi_zones="nyc_8meu-9t5y_taxizones_20260920.csv",
  cultural="nyc_u35m-9t32_cultural_20260920.csv", pedcounts="nyc_cqsj-cfgu_pedcounts_20260920.csv",
  chains="commercial_chains_dohmh_20260920.csv", pip_restrooms="pipRestrooms_9byw-znpj_20260920.csv")
for (k in names(DS)) add(paste0("rows_", k), rows_of(DS[[k]]), comma(rows_of(DS[[k]])), "rows as pulled", paste0("data_raw/", DS[[k]]))
add("n_datasets_listed", length(DS), as.character(length(DS)), "datasets", "this block", "raw datasets listed on the Data & code tab")
nsc <- length(list.files("R", pattern="\\.R$"))
add("n_scripts", nsc, as.character(nsc), "R scripts", "R/", "count of R/*.R")

## =============================================================================
## WRITE
## =============================================================================
derived <- lapply(H, function(x) x[c("value","display","unit","source","note","patterns")])
out <- list(
  about = paste("Single source of truth for headline numbers. Generated by R/Z0_headline_numbers.R;",
                "checked against the site by R/Z1_check_site.R. Do not hand-edit."),
  inputs_md5 = as.list(tools::md5sum(c(
    file.path(dd, c("model_nta_scored_20260920.csv","model_nta_interventions_20260920.csv",
                    "model_nta_benchmark_20260920.csv","nycrestrooms_i7jb-7jku_20260920.csv",
                    "parsed_hours_20260920.csv"))))) |> setNames(c("scored","interventions","benchmark","register","hours")),
  derived = derived,
  external = EXT,
  hub_open_access = hub)
write_json(out, "outputs/headline_numbers.json", auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null")

val_str <- function(v) if (is.list(v)) paste(names(v), unlist(v), sep="=", collapse="; ") else
  paste(if (is.numeric(v)) signif(v, 6) else v, collapse="; ")
csv <- rbind(
  data.frame(key=names(H), value=sapply(H, function(x) val_str(x$value)),
             display_string=sapply(H, `[[`, "display"), unit=sapply(H, `[[`, "unit"),
             source_script=sapply(H, `[[`, "source"), note=sapply(H, `[[`, "note")),
  data.frame(key=paste0("external.", names(EXT)), value=sapply(EXT, function(x) val_str(x$value)),
             display_string=sapply(EXT, `[[`, "display"), unit=sapply(EXT, `[[`, "unit"),
             source_script=sapply(EXT, `[[`, "source"), note=sapply(EXT, `[[`, "note")))
write.csv(csv, "outputs/headline_numbers.csv", row.names=FALSE)
cat(sprintf("wrote outputs/headline_numbers.{json,csv}: %d derived, %d external%s\n",
    length(H), length(EXT), if (is.null(hub)) "" else ", hub_open_access merged"))
for (k in names(H)) cat(sprintf("  %-40s %s\n", k, H[[k]]$display))
