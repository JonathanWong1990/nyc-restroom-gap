# Z1_check_site.R — deterministic checker: does the published site quote the numbers
# in outputs/headline_numbers.json (written by R/Z0_headline_numbers.R), and does it still
# carry any KNOWN-WRONG variant?
#
#   Rscript R/Z1_check_site.R            (site repo defaults to ~/Desktop/restroom-gap-site)
#   SITE_DIR=/path/to/site Rscript R/Z1_check_site.R
#
# Exit status 1 if any STALE value is found or a CORE number is missing from a core file.
# UNSOURCED hits are reported as warnings and do not fail the run.
# Same input -> byte-identical output: no timestamps, fixed file order, sorted hits.
suppressMessages(library(jsonlite)); options(scipen=999, width=160)
P    <- Sys.getenv("RESTROOM_PROJ", unset="."); setwd(P)
SITE <- path.expand(Sys.getenv("SITE_DIR", unset="~/Desktop/restroom-gap-site"))
FILES <- c("index.html", "llms.txt", "REPORT.md", "METHODS.md", "README.md")
# 2026-09-23 site-merge: REPORT.md is now a short pointer to the site, so it is no longer a
# core content file (it is still scanned for stale values).
CORE_FILES <- c("index.html", "llms.txt")
# 2026-09-25 layered walkthrough: the core set follows the new story. Figures from the old narrative
# (29-area costing, walk minutes by area, reconstruction durations, peer table, 3-decimal Spearman) now live
# only in the archived Merged tab, which is skipped. Still scanned everywhere for stale values.
CORE_KEYS  <- c("model_beats_benchmark_share", "ntas_ratio_ge_1_5", "restrooms_operational", "ll58_gap",
                "parks_fail_2026", "pilot_in_29",
                "citywide_daytime_gap_ntas", "extend641_gain_9pm_residents_pts", "build_sites_stronger_anyloc",
                "trial13_detectable_drop", "trial13_cost_6h_parks", "busy_streets_no_open_9pm")
J <- fromJSON("outputs/headline_numbers.json", simplifyVector=FALSE)

## ---- load site text, one element per ORIGINAL line (so file:line is real) ------
blank_blocks <- function(x, tag) {       # replace <tag>...</tag> by the same number of newlines
  rx <- sprintf("(?s)<%s\\b.*?</%s>", tag, tag)
  m <- gregexpr(rx, x, perl=TRUE)[[1]]
  if (m[1] == -1) return(x)
  for (i in rev(seq_along(m))) {
    s <- substr(x, m[i], m[i] + attr(m, "match.length")[i] - 1)
    nl <- lengths(regmatches(s, gregexpr("\n", s)))
    x <- paste0(substr(x, 1, m[i]-1), strrep("\n", nl), substr(x, m[i] + attr(m,"match.length")[i], nchar(x)))
  }
  x
}
blank_archive <- function(x) {            # replace <section data-archive="true">...</section> by its newlines
  rx <- "(?s)<section\\b[^>]*data-archive=\"true\"[^>]*>.*?</section>"
  m <- gregexpr(rx, x, perl=TRUE)[[1]]
  if (m[1] == -1) return(x)
  for (i in rev(seq_along(m))) {
    s <- substr(x, m[i], m[i] + attr(m, "match.length")[i] - 1)
    nl <- lengths(regmatches(s, gregexpr("\n", s)))
    x <- paste0(substr(x, 1, m[i]-1), strrep("\n", nl), substr(x, m[i] + attr(m,"match.length")[i], nchar(x)))
  }
  x
}
decode <- function(x) {
  for (p in list(c("&nbsp;"," "), c("&amp;","&"), c("&lt;","<"), c("&gt;",">"), c("&times;","×"),
                 c("&minus;","−"), c("&ndash;","–"), c("&mdash;","—"), c("&#8211;","–"),
                 c("&#8212;","—"), c("&rsquo;","'"), c("&lsquo;","'"), c("&ldquo;","\""),
                 c("&rdquo;","\""), c("&thinsp;"," "), c(" "," "), c(" "," ")))
    x <- gsub(p[1], p[2], x, fixed=TRUE)
  x
}
load_file <- function(f) {
  x <- paste(readLines(file.path(SITE, f), warn=FALSE, encoding="UTF-8"), collapse="\n")
  if (grepl("\\.html$", f)) {
    # 2026-09-23: the archived 22 Sep walkthrough is kept verbatim for comparison inside
    # <section ... data-archive="true">. Its superseded figures are intentional, so the whole
    # section is blanked (line numbers preserved) before any check runs.
    x <- blank_archive(x)
    for (t in c("svg", "style", "script")) x <- blank_blocks(x, t)
    x <- gsub("<[^>\n]*>", " ", x, perl=TRUE)       # tag -> space, so table cells do not fuse
    x <- gsub(" {2,}", " ", x)
  } else {
    x <- gsub("\\*\\*|`", "", x)                     # markdown emphasis / code ticks
  }
  strsplit(decode(x), "\n", fixed=TRUE)[[1]]
}
TXT <- setNames(lapply(FILES, load_file), FILES)

## ---- search helpers -------------------------------------------------------------
# every match of rx: data.frame(file, line, pos, window)
find_all <- function(rx, W=120) {
  out <- list()
  for (f in FILES) {
    L <- TXT[[f]]
    for (i in seq_along(L)) {
      m <- gregexpr(rx, L[i], perl=TRUE)[[1]]
      if (m[1] == -1) next
      for (p in m) out[[length(out)+1]] <- data.frame(file=f, line=i, pos=p,
        window=substr(L[i], max(1, p-W), p + W),                       # for allow/need tests
        ctx=substr(L[i], max(1, p-45), p + 60), stringsAsFactors=FALSE)  # what is printed
    }
  }
  if (!length(out)) return(data.frame(file=character(), line=integer(), pos=integer(), window=character(), ctx=character()))
  do.call(rbind, out)
}
snip <- function(w, n=90) { w <- gsub("\\s+", " ", w); if (nchar(w) > n) paste0(substr(w, 1, n), "…") else w }

## =============================================================================
## PART A — canonical numbers: where does each appear?
## =============================================================================
D <- J$derived
rows <- list(); missing <- list()
for (k in names(D)) {
  pats <- unlist(D[[k]]$patterns)
  if (!length(pats)) next
  hits <- do.call(rbind, lapply(pats, find_all))
  hits <- unique(hits[order(match(hits$file, FILES), hits$line, hits$pos), c("file","line","pos")])
  cnt <- sapply(FILES, function(f) sum(hits$file == f))
  rows[[k]] <- data.frame(key=k, display=D[[k]]$display, t(cnt), check.names=FALSE)
  if (k %in% CORE_KEYS) for (f in CORE_FILES) if (cnt[[f]] == 0)
    missing[[length(missing)+1]] <- data.frame(file=f, key=k, display=D[[k]]$display)
}
A <- do.call(rbind, rows); rownames(A) <- NULL
A$status <- ifelse(rowSums(A[, FILES]) == 0, "ABSENT",
            ifelse(A$key %in% CORE_KEYS & apply(A[, CORE_FILES] == 0, 1, any), "FAIL-core", "ok"))

## =============================================================================
## PART B — STALE list (known-wrong variants). allow = window regex that makes a hit
## legitimate; need = window regex that must be present for the hit to count.
## =============================================================================
g <- function(k) D[[k]]$display
S <- list(
  list(id="973-not-council", rx="(?<![0-9.,])973(?![0-9])", allow="(?i)council|dashboard",
       fix=sprintf("%s operational (our register); 973 only as 'the Council dashboard says'", g("restrooms_operational"))),
  list(id="0.713", rx="(?<![0-9])0?\\.713(?![0-9])", allow="(?i)prun",
       fix=sprintf("benchmark %s out of sample; %s full-sample", g("benchmark_oos_spearman"), g("benchmark_fullsample_spearman"))),
  list(id="0.793", rx="(?<![0-9])0?\\.793(?![0-9])", fix=paste("model", g("model_oos_spearman"))),
  list(id="0.709", rx="(?<![0-9])0?\\.709(?![0-9])", fix=paste("benchmark", g("benchmark_oos_spearman"))),
  list(id="0.790", rx="(?<![0-9])0?\\.790(?![0-9])", fix=paste("model", g("model_oos_spearman"))),
  list(id="0.710", rx="(?<![0-9])0?\\.710(?![0-9])", fix=paste("benchmark", g("benchmark_oos_spearman"))),
  list(id="0.795-old-seed-range", rx="(?<![0-9])0?\\.795(?![0-9])", fix=paste("seed range", g("model_seed_range"))),
  list(id="0.487", rx="(?<![0-9])0?\\.487(?![0-9])", fix=paste("targeted one-liner", g("oneliner_unserved_fullsample_spearman"))),
  list(id="20_regression-values-as-headline", rx="(?<![0-9])0?\\.(786|704)(?![0-9])", allow="20_regression",
       fix=sprintf("canonical %s / %s (50_tree); 0.786/0.704 only when describing 20_regression.R",
                   g("model_oos_spearman"), g("benchmark_oos_spearman"))),
  list(id="189-of-200", rx="189 of", fix=sprintf("'%s of %s splits' (%s)", g("model_beats_benchmark_share"),
       g("n_oos_splits"), D$model_beats_benchmark_share$note)),
  list(id="11.3M-programme", rx="11\\.3 ?M|11,3[0-9]{2},[0-9]{3}", fix=paste("programme", g("programme_capex_total"))),
  list(id="1,150/1,147-gap", rx="(?<![0-9.,])1,1(50|47)(?![0-9])", fix=paste("2,120 − 975 =", g("ll58_gap"))),
  # 2026-09-23 fix: 3% is now the central rate in 61, 94 and A2 — 3.5% is stale everywhere
  list(id="3.5%-discount", rx="3\\.5 ?%", need="(?i)discount|annualis",
       fix=sprintf("%s central rate (61, 94, A2 all agree)", g("discount_rate_programme"))),
  list(id="164,012-annualised", rx="164,012|\\$164k", fix=paste(g("pooled_median_annualised"), "a year (20 yr @ 3%)")),
  list(id="2.25-per-use", rx="\\$2\\.25 per use", fix=paste(g("pooled_cost_per_use_200day"), "per use at 200/day")),
  list(id="109,693-breakeven", rx="109,693", fix=paste(g("breakeven_annual_cost"), "a year (94, 3%)")),
  list(id="seven-neighbourhoods", rx="(?i)(?<![-\\w])seven neighbourhoods",
       fix=sprintf("%s above 0.95 (%s)", g("posterior_gt_0_95_n"), g("posterior_gt_0_95_names"))),
  list(id="no-rigorous-US", rx="(?i)no rigorous (US|U\\.S\\.)", fix="Amato et al. 2022 (BMC Public Health, SF Pit Stop) exists"),
  list(id="49.42%-uncaveated", rx="49\\.42", allow="(?i)should not be used|not be used|cannot|not comparable|undisclosed|withdrawn|do not (use|cite)",
       fix="Council dashboard figure, method undisclosed; not comparable with ours"),
  list(id="LL58-July-2025", rx="(?i)july 2025", need="(?i)local law 58|LL ?58", fix="LL58 enacted May 2025 (returned unsigned 12 May); July 2025 is LL92"),
  list(id="44-facilities", rx="(?<![0-9])44 facilities", fix=sprintf("%s facilities in the %s hours areas",
       g("hours_extension_facilities"), g("hours_extension_areas"))),
  list(id="$1.9M-trial", rx="\\$1\\.9 ?M", fix=sprintf("10-month trial %s", g("hours_extension_trial_10mo"))),
  list(id="$2.2M-a-year", rx="\\$2\\.2 ?M (a|per) year|\\$2\\.2 ?M ?/ ?yr", fix=sprintf("%s a year", g("hours_extension_annual"))),
  list(id="22.6%-top1", rx="22\\.6 ?%", fix=paste("top 1% of addresses =", g("top1pct_address_share"))),
  list(id="2.98-east-harlem", rx="2\\.98 ?(×|x)", fix=paste("East Harlem (North)", g("east_harlem_ratio"))),
  list(id="tree-55%", rx="(?<![0-9])55 ?%", need="(?i)tree", fix=paste("tree beats benchmark in", g("tree_beats_benchmark_share"))),
  list(id="nine-open-24h", rx="(?i)\\b(9|nine) (facilities|restrooms|toilets)[^.]{0,40}24", fix=paste(g("open_24h"), "open 24 hours")),
  list(id="brighton-6.3", rx="6\\.3(?![0-9])", need="(?i)brighton", fix=g("brighton_beach_expected_ratio")),
  # 2026-09-23 site-merge: figures removed because no script produces them
  list(id="4.86-flip", rx="\\$4\\.86", fix=paste("wage flip point is", g("hours_flip_wage"), "(61 w_flip)")),
  list(id="0.95M-1.64M-threshold-grid", rx="\\$0\\.95 ?M|\\$1\\.64 ?M", fix="no script produces this grid; removed"),
  list(id="poisson-null-12.1", rx="(?<![0-9.])12\\.1(?![0-9])", need="(?i)chance|poisson|null|simulat",
       fix="A5 keeps no object for the Poisson-null mean; removed"),
  list(id="wage-independence", rx="(?i)(does not|doesn't) depend on (the )?wage|wage-(independent|invariant)", allow="(?i)wrong|false|earlier",
       fix=paste("hours stop being cheapest at", g("hours_flip_wage"))),
  # teammate items that failed verification (never on the site)
  list(id="20-50-per-100k", rx="20 ?[–-] ?50 (restrooms )?per 100", fix="unsourced benchmark; do not use"),
  list(id="0.82%-vs-Paris", rx="0\\.82 ?%|25\\.74", fix="mismatched denominators; do not use"),
  # 2026-09-23 round-1 review
  list(id="775-per-excess", rx="\\$775", fix=paste("annualise the excess:", g("cheapest_per_excess_per_year"))),
  list(id="coverage-unweighted-24%", rx="24 ?%", need="(?i)land|coverage|walk", fix=paste("land-weighted", g("coverage_3pm_landweighted"))),
  list(id="steady-climb", rx="(?i)steady climb", fix=g("parks_fail_series")),
  list(id="true-need-posterior", rx="(?i)true need is above", fix="posterior is on the true complaint RATE"),
  list(id="two-thirds-listed", rx="(?i)two-thirds of listed", fix="641 of the 975 operational"),
  list(id="three-of-six-phone", rx="(?i)three of the six", need="(?i)phone", fix=sprintf("%s of the six", g("phone_only_drops_among_six"))),
  list(id="30-40M-envelope", rx="\\$30 ?[–-] ?(\\$)?40 ?M", fix="not derived by any analysis; do not use"),
  # 2026-09-24 final-narrative: claims the tested results retired (Internal_Reviews/final_narrative_outline.md)
  list(id="4-pilot-units-in-Astoria", rx="(?i)\\b(4|four)\\b[^.]{0,25}\\bin Astoria|Astoria[^.]{0,80}\\b(4|four) pilot (units|sites)",
       fix=sprintf("pilot: %s in the six, %s in the 29 (%s)", g("pilot_in_six"), g("pilot_in_29"), D$pilot_in_six$note)),
  list(id="Astoria/Woodside-4-units", rx="Astoria ?/ ?Woodside",
       fix=sprintf("the %s Queens units are in western Queens; %s is in Astoria (East)–Woodside (North)", g("pilot_sites_queens"), g("pilot_in_six"))),
  list(id="natural-test-site", rx="(?i)natural test site", fix="the pilot cannot test the ranking; see pilot_mde_311"),
  list(id="midtown-evening-gap", rx="(?i)Midtown first|(its|Midtown's) (case is the |gap is (in )?the )evening",
       fix=sprintf("Midtown is the BEST served of the six at 9pm (%s); worst: %s", g("walk_9pm_midtown_times"), g("walk_9pm_astoria_east"))),
  list(id="station-screen-picks-corner", rx="(?i)picks the corner|complements (our model|it\\b)|finer scale than our model",
       fix=sprintf("station screen %s vs ridership %s out of sample, worse in %s of splits", g("station_screen_oos_spearman"),
       g("station_ridership_oos_spearman"), g("station_screen_worse_share"))),
  list(id="rather-than-need", rx="(?i)rather than need",
       fix=sprintf("capital follows the existing stock (restroom count OR %s); need %s, never significant", g("capital_restroom_count_or"), g("capital_need_or"))),
  list(id="when-restrooms-close-causal", rx="(?i)that is when (restrooms|they) close|when demand peaks",
       fix=sprintf("timing fits closing times AND nightlife: evening %s, overnight %s vs DSNY", g("urination_vs_dsny_evening"), g("urination_vs_dsny_overnight"))),
  list(id="hours-cheapest-fix", rx="(?i)cheapest (single )?(fix|action)",
       fix=sprintf("hours are the cheapest option to TEST; cheaper only if >= %s as effective as a modular unit", g("hours_breakeven_vs_modular"))),
  list(id="zurich-76.5", rx="(?<![0-9.])76\\.5(?![0-9])", fix=sprintf("not reproducible; like-for-like table: %s", g("peer_per100k_core"))),
  list(id="20-50-range", rx="(?<![0-9$.])20 ?[–-] ?50(?![0-9])", need="(?i)per|100|served|restroom|toilet|standard",
       fix="unsourced well-served range; do not use"),
  list(id="worst-peer-city", rx="(?i)\\bworst\\b", need="(?i)per 100|peer|cities|Paris|Toronto|Berlin|Zurich|Hong Kong|San Francisco",
       fix=sprintf("NYC %s per 100k, %s, but within 2-12%% of Toronto, Berlin and Hong Kong's FEHD list", g("peer_nyc_per100k"), g("peer_nyc_rank"))),
  list(id="11.5-beside-peers", rx="(?<![0-9.])11\\.5(?![0-9])", need="(?i)per 100|100,000|peer|Paris|Toronto|Berlin|Zurich|Hong Kong|San Francisco",
       fix=sprintf("like-for-like NYC figure is %s (core rule); 11.5 counts every register type", g("peer_nyc_per100k"))),
  list(id="93rd-uncaveated", rx="93rd", allow="(?i)park (bathrooms|restrooms)|Trust for Public Land",
       fix="only as 'a 2019 Comptroller report, using Trust for Public Land 2018 park data'"),
  list(id="5.2-years-fix-before-build", rx="(?<![0-9.])5\\.2 years",
       fix=sprintf("by type: reconstruction %s vs new build %s", g("capital_years_reconstruct"), g("capital_years_build_new"))),
  list(id="not-stricter-inspectors", rx="(?i)it is not stricter inspectors", fix="'It does not look like stricter marking' (7 inspectors; Limits §8)"),
  list(id="audit-agrees-trend", rx="(?i)independent audit agrees", fix="the Council audit corroborates the LEVEL (36 of 337 locked), not the trend"),
  # 2026-09-24 final-review fix batch
  list(id="well-supported-hypothesis", rx="(?i)well[- ]supported",
       fix="'Access is the leading hypothesis. Outside evidence is mixed, and our data cannot confirm it, so it should be tested.'"),
  list(id="midtown-unit-belongs", rx="(?i)where a unit belongs",
       fix=sprintf("Midtown: monitor, cause unresolved (best served at 9pm, %s); if a unit is sited, place it at station exits", g("walk_9pm_midtown_times"))),
  list(id="process-narration", rx="(?i)our (hours )?parser|combining the team|the team's (station|research)|we merged|checked against the primary source before inclusion",
       fix="cold-reader voice: state the finding; attribution only in tag pills and the contributor table")
)
U <- list(   # UNSOURCED / assumption-dependent — warn only
  # 2026-09-23 fix: $1.2M is now sourced (NYC Parks $6M / 5 Portland Loos); warn only where the page gives no citation
  list(id="modular-$1.2M", rx="\\$1\\.2 ?M(?![0-9])|\\$?1,200,000", allow="(?i)portland loo|pilot|parks",
       fix=sprintf("cite NYC Parks' $6M five-unit Portland Loo pilot; the 2026 pilot's %s per unit-year is a SERVICE contract", g("modular_pilot_implied_per_unit_year"))),
  list(id="$34.8M-all-modular", rx="\\$34\\.8 ?M", allow="(?i)29 (×|x) ", fix="= 29 x $1.2M (Parks Portland Loo pilot budget per unit)"),
  list(id="hours-as-$0", rx="(?i)hours[^.]{0,40}\\$0(?![.,0-9])|\\$0(?![.,0-9])[^.]{0,40}hours",
       fix=sprintf("recurring cost %s/yr, %s over 10 yrs undiscounted (%s PV at %s)", g("hours_extension_annual"),
       g("hours_extension_10yr_undiscounted"), g("hours_extension_10yr_pv"), g("discount_rate_programme")))
)
run_rules <- function(R, sev) {
  out <- list()
  for (r in R) {
    h <- find_all(r$rx)
    if (nrow(h) && !is.null(r$need))  h <- h[grepl(r$need,  h$window, perl=TRUE), , drop=FALSE]
    if (nrow(h) && !is.null(r$allow)) h <- h[!grepl(r$allow, h$window, perl=TRUE), , drop=FALSE]
    if (nrow(h)) out[[r$id]] <- data.frame(severity=sev, rule=r$id, file=h$file, line=h$line,
      context=sapply(h$ctx, snip, n=105, USE.NAMES=FALSE), fix=r$fix, stringsAsFactors=FALSE)
  }
  if (!length(out)) return(NULL)
  o <- do.call(rbind, out); o[order(match(o$file, FILES), o$line, o$rule), ]
}
ST <- run_rules(S, "STALE"); UW <- run_rules(U, "UNSOURCED")

## =============================================================================
## REPORT
## =============================================================================
cat("SITE:", SITE, "\n")
cat("SOURCE OF TRUTH: outputs/headline_numbers.json\n\n")
cat("=== A. CANONICAL NUMBERS — occurrences per file (index = index.html text, SVG stripped) ===\n")
hdr <- sprintf("%-36s %-16s %5s %5s %6s %7s %6s  %s", "key", "display", "index", "llms", "REPORT", "METHODS", "README", "status")
cat(hdr, "\n", strrep("-", nchar(hdr)), "\n", sep="")
for (i in seq_len(nrow(A))) cat(sprintf("%-36s %-16s %5d %5d %6d %7d %6d  %s\n", A$key[i],
  substr(A$display[i], 1, 16), A[i,"index.html"], A[i,"llms.txt"], A[i,"REPORT.md"],
  A[i,"METHODS.md"], A[i,"README.md"], A$status[i]))
nopat <- setdiff(names(D), A$key)
cat(sprintf("\n(%d further keys carry no search pattern — composite values or names; see the CSV)\n", length(nopat)))

if (length(missing)) {
  M <- do.call(rbind, missing)
  cat("\n=== B. CORE NUMBERS MISSING FROM A CORE FILE (FAIL) ===\n")
  for (i in seq_len(nrow(M))) cat(sprintf("  FAIL  %-10s lacks %-30s (%s)\n", M$file[i], M$key[i], M$display[i]))
} else M <- NULL

show <- function(X, title) {
  cat(sprintf("\n=== %s ===\n", title))
  if (is.null(X)) { cat("  none\n"); return(invisible()) }
  for (i in seq_len(nrow(X))) cat(sprintf("  %-9s %-28s %s:%d\n            \"%s\"\n            -> %s\n",
    X$severity[i], X$rule[i], X$file[i], X$line[i], X$context[i], X$fix[i]))
}
show(ST, "C. STALE VALUES (FAIL)")
show(UW, "D. UNSOURCED / ASSUMPTION-DEPENDENT (warning only)")

cat("\n=== SUMMARY per file ===\n")
cat(sprintf("%-11s %6s %13s %10s\n", "file", "STALE", "CORE-MISSING", "UNSOURCED"))
for (f in FILES) cat(sprintf("%-11s %6d %13d %10d\n", f,
  if (is.null(ST)) 0 else sum(ST$file == f), if (is.null(M)) 0 else sum(M$file == f),
  if (is.null(UW)) 0 else sum(UW$file == f)))
if (!is.null(ST)) { cat("\nSTALE by rule:\n"); tb <- table(ST$rule); for (r in names(tb)) cat(sprintf("  %-34s %d\n", r, tb[[r]])) }
nfail <- (if (is.null(ST)) 0 else nrow(ST)) + (if (is.null(M)) 0 else nrow(M))
cat(sprintf("\nRESULT: %s  (%d stale, %d core-missing, %d unsourced warnings)\n",
  if (nfail) "FAIL" else "PASS", if (is.null(ST)) 0 else nrow(ST), if (is.null(M)) 0 else nrow(M),
  if (is.null(UW)) 0 else nrow(UW)))
quit(status = if (nfail) 1 else 0)
