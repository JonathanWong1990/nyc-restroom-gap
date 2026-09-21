# 98_coldread_fixes.R — gaps identified by cold readers.
suppressMessages({library(sf); library(dplyr); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_with_commercial_20260920.csv"))

## ---- 1. EVENING GAP recomputed on REAL hours only -------------------------
cat("=== 1. EVENING GAP, boilerplate facilities EXCLUDED ===\n")
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"), stringsAsFactors=FALSE)
rr$fid <- seq_len(nrow(rr))
op <- rr$status=="Operational" & rr$open=="Year Round"
boiler <- grepl("Open later seasonally", rr$hours_of_operation, ignore.case=TRUE)
real_ids <- rr$fid[op & !boiler]
ph <- read.csv(file.path(D,"parsed_hours_20260920.csv")) |> filter(parsed, is_open)
openat <- function(ids, hh) sum(ph$facility_id %in% ids & ph$open_hour<=hh & ph$close_hour>hh)/7
cat(sprintf("facilities with genuine hours strings: %d (of %d operational year-round)\n",
            length(real_ids), sum(op)))
for(hh in c(12,15,18,20,21,23)) cat(sprintf("  %02d:00  %5.0f of %d open (%.0f%%)\n",
    hh, openat(real_ids,hh), length(real_ids), 100*openat(real_ids,hh)/length(real_ids)))

## ---- 2. BOOTSTRAP the ranking -----------------------------------------------
cat("\n=== 2. HOW STABLE IS THE RANKING? (500 bootstrap resamples) ===\n")
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
dd <- d |> filter(!is.na(inc10k), !is.na(pov), pop_total>0)
top10 <- matrix(0, nrow=nrow(dd), ncol=1); rownames(top10) <- dd$nta2020
B <- 500
for(b in seq_len(B)){
  i <- sample(nrow(dd), replace=TRUE)
  f <- try(glm.nb(F, data=dd[i,]), silent=TRUE); if(inherits(f,"try-error")) next
  p <- try(predict(f, newdata=dd, type="response"), silent=TRUE); if(inherits(p,"try-error")) next
  r <- dd$events_311/pmax(p,.01)
  top10[order(-r)[1:10],1] <- top10[order(-r)[1:10],1] + 1
}
dd$p_top10 <- 100*top10[,1]/B
cat("Probability each shortlist neighbourhood really belongs in the top 10:\n")
print(dd |> arrange(desc(resid_ratio)) |>
  transmute(neighbourhood=substr(ntaname,1,32), ratio=round(resid_ratio,2),
            observed=events_311, pct_in_top10=round(p_top10)) |> head(12), row.names=FALSE)

## ---- 3. MORAN'S I on the residuals -----------------------------------------
cat("\n=== 3. ARE THE RESIDUALS SPATIALLY CLUSTERED? (Moran's I) ===\n")
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> dplyr::select(nta2020) |> inner_join(dd |> dplyr::select(nta2020, resid_ratio), by="nta2020")
nb <- st_touches(nta)
x <- log(pmax(nta$resid_ratio, 0.05))   # 4 areas have a zero ratio; floor before logging
x <- x - mean(x)
W <- 0; num <- 0
for(i in seq_along(nb)){ j <- nb[[i]]; if(!length(j)) next
  w <- 1/length(j); num <- num + sum(w*x[i]*x[j]); W <- W + sum(w) }
I <- (length(x)/W) * num / sum(x^2)
EI <- -1/(length(x)-1)
perm <- replicate(999, { xs <- sample(x); n2 <- 0
  for(i in seq_along(nb)){ j <- nb[[i]]; if(!length(j)) next
    n2 <- n2 + sum((1/length(j))*xs[i]*xs[j]) }
  (length(xs)/W) * n2 / sum(xs^2) })
cat(sprintf("Moran's I = %.3f (expected under no clustering %.3f), permutation p = %.3f\n",
            I, EI, (1+sum(perm>=I))/1000))
cat(ifelse((1+sum(perm>=I))/1000 < 0.05,
  "  -> residuals ARE spatially clustered; neighbouring areas are not independent.\n",
  "  -> no significant spatial clustering; treating areas as independent is defensible.\n"))

## ---- 4. Does ADA status explain the high-supply/high-need areas? -----------
cat("\n=== 4. ACCESSIBILITY IN THE SHORTLIST ===\n")
rs <- rr |> filter(status=="Operational", !is.na(latitude), !is.na(longitude))
rsf <- st_as_sf(rs, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
          st_transform(2263) |> dplyr::select(nta2020), join=st_within) |> st_drop_geometry()
acc <- rsf |> filter(!is.na(nta2020)) |> group_by(nta2020) |>
  summarise(n=n(), full=sum(accessibility=="Fully Accessible", na.rm=TRUE), .groups="drop") |>
  mutate(pct_full=100*full/n)
top <- dd |> arrange(desc(resid_ratio)) |> head(8) |> left_join(acc, by="nta2020")
print(top |> transmute(neighbourhood=substr(ntaname,1,30), ratio=round(resid_ratio,2),
      restrooms=n, fully_accessible=full, pct=round(pct_full)), row.names=FALSE)
cat(sprintf("\ncitywide share fully accessible: %.0f%%\n",
    100*sum(acc$full)/sum(acc$n)))
