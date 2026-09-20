# 94_breakeven.R — switching-value analysis. We cannot value the benefit, so we invert the
# question: how large would the benefit have to be to justify the cost? (UK Green Book method.)
suppressMessages({library(dplyr)}); options(scipen=999); D <- "data_raw"

ct <- read.csv(file.path(D,"capitaltracker_4hcv-tc5r_20260920.csv")) |>
  distinct(trackerid, .keep_all=TRUE) |>
  filter(grepl("restroom|comfort station|bathroom", paste(title,summary), ignore.case=TRUE))
num <- suppressWarnings(as.numeric(gsub("[^0-9.]","",ct$totalfunding)))
f <- ifelse(grepl("^[[:space:]]*\\$?[0-9,.]+[[:space:]]*$", ct$totalfunding), num, NA)
MED <- median(f, na.rm=TRUE); P25 <- quantile(f,.25,na.rm=TRUE); P75 <- quantile(f,.75,na.rm=TRUE)
crf <- function(p,n,r) p*(r*(1+r)^n)/((1+r)^n-1)

cat("=== BREAK-EVEN: what would a restroom have to achieve to pay for itself? ===\n\n")
cat(sprintf("NYC restroom capital projects (n=%d parseable of %d): median $%s, IQR $%s-$%s\n\n",
  sum(!is.na(f)), nrow(ct), format(round(MED),big.mark=","),
  format(round(P25),big.mark=","), format(round(P75),big.mark=",")))

cat("Annualised capital cost (capital recovery factor):\n")
for(life in c(20,30)) for(r in c(0.02,0.035,0.05))
  cat(sprintf("  $%s over %d yr @ %.1f%%  =  $%s / year\n",
      format(round(MED),big.mark=","), life, 100*r,
      format(round(crf(MED,life,r)),big.mark=",")))

A <- crf(MED,20,0.035)
cat(sprintf("\nUsing $%s/yr (median project, 20 yr, 3.5%%) as the annual cost.\n", format(round(A),big.mark=",")))

cat("\n--- Break-even expressed in units a decision-maker can judge ---\n")
for(v in c(50,100,250,500,1000)) cat(sprintf(
  "  If one avoided public-urination incident is worth $%-5s -> need %s avoided incidents/yr\n",
  format(v,big.mark=","), format(round(A/v), big.mark=",")))

cat("\n--- Or per use, if the facility simply gets used ---\n")
for(u in c(50,100,200,400)) cat(sprintf(
  "  At %3d uses/day (%s/yr) -> cost per use = $%.2f\n",
  u, format(u*365,big.mark=","), A/(u*365)))

cat("\n--- Sanity anchor from the literature (benefit transfer, NOT our estimate) ---\n")
cat("  Amato et al., BMC Public Health 2022 (San Francisco Pit Stop):\n")
cat("  13 new restrooms -> 12.47 fewer 311 feces reports per week within 500m\n")
sf_per_fac_yr <- 12.47/13*52
cat(sprintf("  => ~%.0f avoided reports per facility per year\n", sf_per_fac_yr))
cat(sprintf("  At that rate, break-even needs each avoided report to be worth $%.0f\n", A/sf_per_fac_yr))
cat("  CAVEAT: SF measured DEFECATION reports in a far higher-incidence setting.\n")
cat("  NYC's whole-city urination complaint volume is ~540/yr. Do not transfer this directly.\n")

cat("\n--- What NYC's own numbers imply ---\n")
LL <- 2120; HAVE <- 973
cat(sprintf("  Local Law 58 gap: %d - %d = %s facilities by 2035\n", LL, HAVE, format(LL-HAVE,big.mark=",")))
cat(sprintf("  At the median project cost that is $%s of capital,\n",
    format(round((LL-HAVE)*MED/1e9,2), nsmall=2)))
cat(sprintf("  or about $%s billion — roughly $%s per NYC resident.\n",
    format(round((LL-HAVE)*MED/1e9,2), nsmall=2),
    format(round((LL-HAVE)*MED/8483844), big.mark=",")))
