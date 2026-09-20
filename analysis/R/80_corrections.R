# 80_corrections.R — Tier 1+2 fixes from the 2026-09-20 adversarial audit.
suppressMessages({library(dplyr); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"

cat("=========== 1. REAL CLUSTERED SEs FOR THE NB MODEL ===========\n")
d <- read.csv(file.path(D,"model_nta_scored_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
m <- glm.nb(F, data=d)
# NB2 score wrt beta: x_i (y-mu)/(1+mu/theta).  bread = vcov(fit)
cl_nb <- function(fit, cl){
  X <- model.matrix(fit); mu <- fitted(fit); y <- fit$y; th <- fit$theta
  u <- X * ((y-mu)/(1+mu/th))
  uc <- rowsum(u, cl); G <- length(unique(cl))
  V <- vcov(fit) %*% crossprod(uc) %*% vcov(fit) * (G/(G-1))
  sqrt(diag(V))
}
se_cl <- cl_nb(m, d$cdta2020); co <- summary(m)$coefficients
cat("clusters (community districts):", length(unique(d$cdta2020)), "\n\n")
cmp <- data.frame(term=rownames(co), IRR=round(exp(co[,1]),3),
  p_naive=round(co[,4],4), p_clustered=round(2*pnorm(-abs(co[,1]/se_cl)),4), row.names=NULL)
print(cmp[!grepl("Intercept",cmp$term),], row.names=FALSE)

cat("\n=========== 2. COST FIGURES DERIVED FROM DATA ===========\n")
ct <- read.csv(file.path(D,"capitaltracker_4hcv-tc5r_20260920.csv")) |>
  distinct(trackerid, .keep_all=TRUE) |>
  filter(grepl("restroom|comfort station|bathroom", paste(title,summary), ignore.case=TRUE))
num <- suppressWarnings(as.numeric(gsub("[^0-9.]","",ct$totalfunding)))
ct$fund <- ifelse(grepl("^\\s*\\$?[0-9,.]+\\s*$", ct$totalfunding), num, NA)
txt <- tolower(paste(ct$title, ct$summary))
ct$kind <- case_when(
  grepl("roof|hvac|boiler|electrical|plumbing|window|door", txt) ~ "component",
  grepl("new |construct(ion)? of|build", txt) ~ "new build",
  grepl("reconstruct|renovat|rehabilit|upgrad|restor", txt) ~ "reconstruction",
  TRUE ~ "other")
cat("restroom projects:", nrow(ct), " with a parseable dollar figure:", sum(!is.na(ct$fund)),
    sprintf(" (%.0f%% are banded text and excluded)\n", 100*mean(is.na(ct$fund))))
print(ct |> filter(!is.na(fund)) |> group_by(kind) |>
  summarise(n=n(), median=round(median(fund)), p25=round(quantile(fund,.25)),
            p75=round(quantile(fund,.75)), .groups="drop") |> arrange(desc(median)),
  row.names=FALSE)
NEW <- median(ct$fund[ct$kind=="new build"], na.rm=TRUE)
REC <- median(ct$fund[ct$kind=="reconstruction"], na.rm=TRUE)
CMP <- median(ct$fund[ct$kind=="component"], na.rm=TRUE)
cat(sprintf("\n-> DERIVED: new build $%s | reconstruction $%s | component $%s\n",
  format(round(NEW),big.mark=","), format(round(REC),big.mark=","),
  ifelse(is.na(CMP),"n/a",format(round(CMP),big.mark=","))))

cat("\n=========== 3. HOURS RULE WITHOUT PARKS BOILERPLATE ===========\n")
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"), stringsAsFactors=FALSE)
op <- rr$status=="Operational" & rr$open=="Year Round"
boiler <- grepl("Open later seasonally", rr$hours_of_operation, ignore.case=TRUE)
cat("operational+year-round:", sum(op), " of which boilerplate:", sum(op&boiler),
    sprintf(" (%.1f%%)\n", 100*mean(boiler[op])))
cat("facilities with REAL parseable hours:", sum(op & !boiler), "\n")
ph <- read.csv(file.path(D,"parsed_hours_20260920.csv"))
real <- ph |> filter(facility_id %in% which(op & !boiler), parsed, is_open)
cat(sprintf("median open-day among those: %.1f h (vs %.1f h including boilerplate)\n",
  median(real$close_hour-real$open_hour),
  median((ph |> filter(facility_id %in% which(op), parsed, is_open) |>
          mutate(d=close_hour-open_hour))$d)))

cat("\n=========== 4. CORRECTED DESCRIPTIVES ===========\n")
sel <- ph$parsed & ph$is_open & ph$facility_id %in% which(op)
dur <- ph$close_hour - ph$open_hour
f24 <- unique(ph$facility_id[which(sel & dur>=24)])
cat("24-hour facilities:", length(f24), " (published: 9 — an NA was counted)\n")
sat <- ph |> filter(day_of_week==7, parsed, is_open, facility_id %in% which(op))
cat("open AT 11pm Saturday (close_hour>=23):", sum(sat$close_hour>=23),
    " | open PAST 11pm (>23):", sum(sat$close_hour>23), " (published: 21)\n")
tl <- read.csv(file.path(D,"tlc_c5iv-bn4s_zonemonth_20260920.csv"))
cat(sprintf("TLC: %s endpoints = ~%s actual trips (pickups %s + dropoffs %s)\n",
  format(sum(tl$trip_count),big.mark=","), format(round(sum(tl$trip_count)/2),big.mark=","),
  format(sum(tl$trip_count[tl$pickup_dropoff=="Pick-up"]),big.mark=","),
  format(sum(tl$trip_count[tl$pickup_dropoff=="Drop-off"]),big.mark=",")))
cat("\nHighest complaint count, NTA level (deduped):\n")
print(d |> arrange(desc(events_311)) |> transmute(ntaname=substr(ntaname,1,34),
      deduped=events_311, raw=events_311_raw) |> head(4), row.names=FALSE)

cat("\n=========== 5. STOCK/FLOW + EXCESS COLUMN ===========\n")
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
dt <- as.Date(substr(e$created_date,1,10)); YRS <- as.numeric(diff(range(dt,na.rm=TRUE)))/365.25
cat(sprintf("observation window: %.2f years -> annualise by dividing excess by %.2f\n", YRS, YRS))
d$excess_total <- pmax(d$events_311 - d$pred, 0); d$excess_yr <- d$excess_total/YRS
cat("\nShortlist ranked by ABSOLUTE deficit (what a build decision needs):\n")
print(d |> arrange(desc(excess_total)) |> transmute(ntaname=substr(ntaname,1,32),
      ratio=round(resid_ratio,2), excess_total=round(excess_total),
      excess_per_yr=round(excess_yr,1), restrooms) |> head(10), row.names=FALSE)
write.csv(d, file.path(D,"model_nta_scored_v2_20260920.csv"), row.names=FALSE)
