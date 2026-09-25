# 03_final_rule.R -- priority order (owner review, 25 Sep): fix what exists, then build, then extend hours.
# The order is a stated preference for using existing restrooms first; it is not a cost optimisation.
#   FIX    : repairing/reopening Parks restrooms restores >= FIX_PP points of resident coverage
#            (fix_gain = coverage lost if broken-but-listed restrooms are removed + coverage gained by reopening
#             long-term-closed ones). A broken restroom that other restrooms already back up does NOT qualify.
#   BUILD  : after any fix, >= GAP residents still have no restroom within 500 m even by day.
#   EXTEND : covered by day but >= GAP not covered at 9pm, and keeping placeholder park restrooms open to 10pm
#            recovers at least half of that.
#   VERIFY : none of the above -- complaints without a supply gap.
# Primary = FIX > BUILD > EXTEND > VERIFY; areas can carry two actions ("FIX, then BUILD").
# Reads cache/layers.rds from 01_layers.R; writes cache/layers_final.rds and outputs/*_final.csv.
suppressPackageStartupMessages({library(data.table)})
LY <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Build_Plan/layered"
X <- readRDS(file.path(LY, "cache/layers.rds")); L <- as.data.table(X$L)
stopifnot(sum(L$in_29) == 29)

rule <- function(d, GAP = 0.40, FIX_PP = 10, l2 = "L2_residents", l3 = "L3_residents", rec = "L3_ext_recov_frac") {
  fix_gain  <- d$L4_lost_pp + d$L4_reopen_gain_pp
  f <- fix_gain >= FIX_PP
  gap_after <- d[[l2]] - ifelse(f, d$L4_reopen_gain_pp / 100, 0)   # the gap shrinks only if the fix is applied
  b <- gap_after >= GAP
  e <- d[[l3]] >= GAP & d[[rec]] >= 0.5
  prim <- ifelse(f, "FIX", ifelse(b, "BUILD", ifelse(e, "EXTEND HOURS", "VERIFY")))
  lab  <- ifelse(f & b, "FIX, then BUILD", prim)
  data.table(fix_gain_pp = round(fix_gain, 1), L2_after_fix = round(gap_after, 3),
             final_fix = f, final_build = b, final_extend = e, final_action = prim, final_label = lab)
}
F0 <- rule(L); L <- cbind(L[, !intersect(names(L), names(F0)), with = FALSE], F0)
# Build split by strength of the complaint signal (review A, 25 Sep). The 29's empirical-Bayes P(ratio > 1.5) for BUILD
# areas falls in two clusters, 0.80-1.00 and 0.24-0.52; the split sits in that natural break (any cut from 0.53 to
# 0.79 gives the same groups). This orders the build list; it is not a significance test.
L[, build_signal := ifelse(final_action == "BUILD", ifelse(eb_p_gt_1_5 >= 0.75, "stronger", "weaker"), NA_character_)]
L[, display_action := fifelse(final_action == "BUILD" & build_signal == "weaker", "BUILD, VERIFY FIRST",
                       fifelse(final_action == "VERIFY", "LOOK ELSEWHERE", final_action))]
d29 <- L[in_29 == TRUE]
cat("Final (cost-ordered) primary action, 29 NTAs:\n"); print(table(d29$final_action))
cat("\nlabels:\n"); print(table(d29$final_label))
for (a in c("FIX", "BUILD", "EXTEND HOURS", "VERIFY"))
  cat(sprintf("\n%-13s %s", a, paste(d29[final_action == a][order(-resid_ratio)]$ntaname, collapse = "; ")))
cat("\n\nchanged vs the first rule (01_layers.R):\n")
ch <- d29[final_action != primary_action, .(ntaname, from = primary_action, to = final_action)]; print(ch)

# sensitivity of the final rule
grid <- CJ(GAP = c(.30, .40, .50), FIX_PP = c(5, 10, 15), radius = c(500, 400))
sens <- rbindlist(lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i]
  r <- if (g$radius == 500) rule(d29, g$GAP, g$FIX_PP) else
         rule(d29, g$GAP, g$FIX_PP, "L2_residents_400m", "L3_residents_400m", "L3_ext_recov_frac_400m")
  data.table(g, n_FIX = sum(r$final_action == "FIX"), n_BUILD = sum(r$final_action == "BUILD"),
             n_EXTEND = sum(r$final_action == "EXTEND HOURS"), n_VERIFY = sum(r$final_action == "VERIFY"),
             n_changed = sum(r$final_action != d29$final_action),
             changed = paste(sprintf("%s: %s->%s", d29$ntaname, d29$final_action, r$final_action)[r$final_action != d29$final_action], collapse = "; "))
}))
cat("\nSensitivity (29 NTAs; base = GAP 0.40, FIX 10 pp, 500 m):\n"); print(sens[, -"changed"])
fwrite(sens, file.path(LY, "outputs/sensitivity_final.csv"))
fwrite(d29[order(final_action, -resid_ratio)], file.path(LY, "outputs/diagnosis_29_final.csv"))
X$L <- L; saveRDS(X, file.path(LY, "cache/layers_final.rds"))
