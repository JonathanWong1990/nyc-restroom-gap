# 61_cost_annualised.R — fixes the "hours extension costs $0 so it always wins" trap.
# Everything is converted to ANNUAL cost. The one unsourceable input (staffing) is an
# EXPLICIT, LABELLED assumption with sensitivity, not a hidden number.
suppressMessages({library(dplyr)})
options(scipen=999); D <- "data_raw"
d <- read.csv(file.path(D,"model_nta_interventions_20260920.csv"))

# ---- ASSUMPTIONS (stated, not buried) -------------------------------------
LIFE_BUILD <- 20; LIFE_REPAIR <- 10; DISC <- 0.03
WAGE <- 35          # loaded $/hour for an attendant  <-- ASSUMPTION, sensitivity below
EXTRA_H <- 4        # hours/day added by an "extend hours" intervention <-- ASSUMPTION
CAP_MOD <- 1200000; CAP_REP <- 60500
annualise <- function(capex, life, r=DISC) capex * (r*(1+r)^life)/((1+r)^life - 1)

cat("ASSUMPTIONS\n")
cat(sprintf("  modular unit CapEx        $%s over %d yr @ %.0f%% -> $%s/yr\n",
    format(CAP_MOD,big.mark=","), LIFE_BUILD, 100*DISC,
    format(round(annualise(CAP_MOD,LIFE_BUILD)),big.mark=",")))
cat(sprintf("  component repair CapEx    $%s over %d yr @ %.0f%% -> $%s/yr\n",
    format(CAP_REP,big.mark=","), LIFE_REPAIR, 100*DISC,
    format(round(annualise(CAP_REP,LIFE_REPAIR)),big.mark=",")))
cat(sprintf("  extend hours: %d h/day x 365 x $%d/h -> $%s/yr  [UNSOURCED - assumption]\n\n",
    EXTRA_H, WAGE, format(EXTRA_H*365*WAGE, big.mark=",")))

cost_of <- function(iv, wage=WAGE, extra=EXTRA_H) case_when(
  iv=="Build new / modular unit" ~ annualise(CAP_MOD, LIFE_BUILD),
  iv=="Reconstruct or repair"    ~ annualise(CAP_REP, LIFE_REPAIR),
  iv=="Extend operating hours"   ~ extra*365*wage,
  TRUE ~ NA_real_)

short <- d |> filter(resid_ratio >= 1.5, excess > 0) |>
  mutate(annual_cost = cost_of(intervention),
         per_excess  = annual_cost/excess) |>
  arrange(per_excess)

cat("=== ANNUAL cost per excess complaint (lower = better) ===\n")
print(short |> transmute(neighbourhood=substr(ntaname,1,30), action=intervention,
        annual=format(round(annual_cost),big.mark=","), excess=round(excess),
        per_excess=format(round(per_excess),big.mark=",")) |> head(14), row.names=FALSE)

cat("\n=== Mix and totals ===\n")
print(short |> group_by(intervention) |>
  summarise(n=n(), annual=format(round(sum(annual_cost)),big.mark=","),
            excess=round(sum(excess)), .groups="drop"), row.names=FALSE)
cat(sprintf("\nTOTAL annual cost for the shortlist: $%s covering %d excess complaints (6.71-YEAR STOCK)\n",
    format(round(sum(short$annual_cost, na.rm=TRUE)),big.mark=","), round(sum(short$excess, na.rm=TRUE))))

## ---- SENSITIVITY: does the ranking survive different wage assumptions? ----
cat("\n=== SENSITIVITY: top-5 ranking under different staffing assumptions ===\n")
for(w in c(20, 35, 60, 100)){
  s <- d |> filter(resid_ratio>=1.5, excess>0) |>
    mutate(a=cost_of(intervention, wage=w), pe=a/excess) |> arrange(pe)
  cat(sprintf("$%3d/hr -> %s\n", w,
      paste(substr(s$ntaname,1,22)[1:5], collapse=" | ")))
}
w_flip <- NA
for(w in seq(10, 400, by=5)){
  s <- d |> filter(resid_ratio>=1.5, excess>0) |>
    mutate(a=cost_of(intervention, wage=w), pe=a/excess) |> arrange(pe)
  if(s$intervention[1] != "Extend operating hours"){ w_flip <- w; break }
}
cat(sprintf("\nHours-extension stops being the cheapest option at about $%s/hour staffing.\n",
            ifelse(is.na(w_flip), ">400", w_flip)))
write.csv(short, file.path(D,"model_shortlist_costed_20260920.csv"), row.names=FALSE)
