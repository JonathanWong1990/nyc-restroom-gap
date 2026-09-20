# 15_did_openings.R — second, DIFFERENT treatment: capital-project construction COMPLETION
# (a restroom actually (re)opens renovated), rather than inspection-based closure.
suppressMessages({library(sf); library(dplyr); library(tidyr)})
options(scipen=999); D <- "data_raw"; RAD_FT <- 500/0.3048

RX <- "restroom|comfort station|bathroom|comfort_station"
ct <- read.csv(file.path(D,"capitaltracker_4hcv-tc5r_20260920.csv")) |>
  distinct(trackerid, .keep_all=TRUE)
cat("all projects:", nrow(ct), "\n")
ct <- ct |> filter(grepl(RX, paste(title, summary), ignore.case=TRUE))
cat("RESTROOM projects only:", nrow(ct), "\n")
ct <- ct |>
  mutate(done=as.Date(substr(constructionactualcompletion,1,10)))
cat("capital projects (deduped):", nrow(ct),
    " with construction completion date:", sum(!is.na(ct$done)), "\n")
ct <- ct |> filter(!is.na(done), done>=as.Date("2020-07-01"), done<=as.Date("2025-12-31"),
                   !is.na(latitude), !is.na(longitude))
cat("completions inside the 311 window (2020-07..2025-12):", nrow(ct), "\n")
if(nrow(ct) < 15) { cat("\nTOO FEW TREATED UNITS — cannot estimate. Stopping honestly.\n"); quit(save="no") }
cat("completion years:\n"); print(table(format(ct$done,"%Y")))

site <- st_as_sf(ct, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  mutate(sid=paste0("P",row_number()), open_ym=format(done,"%Y-%m")) |> select(sid, open_ym)
buf <- st_buffer(site, RAD_FT)

e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv")) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
         !is.na(latitude), !is.na(longitude)) |>
  mutate(date=as.Date(substr(created_date,1,10)), ym=format(date,"%Y-%m")) |>
  distinct(incident_address, ym, .keep_all=TRUE)
esf <- st_as_sf(e, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263)
hit <- st_join(esf, buf, join=st_within, left=FALSE) |> st_drop_geometry()
cat("events near a treated site:", nrow(hit), " sites with any:", n_distinct(hit$sid), "\n")

months <- format(seq(as.Date("2020-01-01"), as.Date("2026-06-01"), by="month"), "%Y-%m")
pan <- expand_grid(sid=site$sid, ym=months) |>
  left_join(count(hit, sid, ym, name="complaints"), by=c("sid","ym")) |>
  mutate(complaints=replace_na(complaints,0L)) |>
  left_join(st_drop_geometry(site), by="sid") |>
  mutate(mi=as.integer(substr(ym,1,4))*12+as.integer(substr(ym,6,7)),
         oi=as.integer(substr(open_ym,1,4))*12+as.integer(substr(open_ym,6,7)),
         t=mi-oi, post=as.integer(t>=0))
cat("panel:", nrow(pan), "site-months  mean complaints:", round(mean(pan$complaints),3),
    " share zero:", sprintf("%.1f%%\n", 100*mean(pan$complaints==0)))

keep <- pan |> group_by(sid) |> summarise(tot=sum(complaints), .groups="drop") |> filter(tot>0)
cat("sites with any nearby complaints (identifying sample):", nrow(keep), "\n")
pp <- pan |> filter(sid %in% keep$sid) |> mutate(sid=factor(sid), ym=factor(ym))
if(nrow(keep) < 10){ cat("\nTOO FEW — stopping honestly.\n"); quit(save="no") }

cluster_se <- function(fit, cl){
  X <- model.matrix(fit); u <- X*residuals(fit,type="response")
  br <- summary(fit)$cov.unscaled; uc <- rowsum(u, cl); G <- length(unique(cl))
  sqrt(diag(br %*% crossprod(uc) %*% br * (G/(G-1))))
}
cat("\n=== TWFE Poisson: complaints ~ post(renovated restroom opens) + site FE + month FE ===\n")
f <- glm(complaints ~ post + sid + ym, family=poisson, data=pp)
s <- cluster_se(f, pp$sid); b <- coef(f)["post"]; se <- s[names(coef(f))=="post"]
cat(sprintf("coef(post) = %.4f  clustered SE = %.4f  z = %.2f  p = %.4f\n",
            b, se, b/se, 2*pnorm(-abs(b/se))))
cat(sprintf("=> reopening is associated with a %.1f%% change in nearby complaints (95%% CI %.1f%% to %.1f%%)\n",
            100*(exp(b)-1), 100*(exp(b-1.96*se)-1), 100*(exp(b+1.96*se)-1)))
