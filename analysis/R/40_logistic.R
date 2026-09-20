# 40_logistic.R — Session 6: does NYC invest where NEED is, or where PARKS are?
# Outcome: did this neighbourhood receive a Parks capital RESTROOM project?
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); set.seed(6093); D <- "data_raw"
sc  <- read.csv(file.path(D,"model_nta_scored_20260920.csv"))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> select(nta2020)

## --- treatment: restroom capital projects -> NTA ---------------------------
RX <- "restroom|comfort station|bathroom"
ct <- read.csv(file.path(D,"capitaltracker_4hcv-tc5r_20260920.csv")) |>
  distinct(trackerid, .keep_all=TRUE) |>
  filter(grepl(RX, paste(title, summary), ignore.case=TRUE),
         !is.na(latitude), !is.na(longitude))
cat("restroom capital projects with coords:", nrow(ct), "\n")
ctp <- st_as_sf(ct, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020))
proj <- ctp |> count(nta2020, name="n_projects")
cat("neighbourhoods receiving >=1 project:", nrow(proj), "of 197\n")

## --- park acreage per NTA (the rival explanation) --------------------------
pk <- readRDS(file.path(D,"parksprops_sf_20260920.rds")) |> st_transform(2263)
pk <- st_make_valid(pk)
pin <- suppressWarnings(st_intersection(pk |> select(geometry), nta))
pin$acres <- as.numeric(st_area(pin))/43560
park <- pin |> st_drop_geometry() |> group_by(nta2020) |>
  summarise(park_acres=sum(acres), .groups="drop")
cat("NTAs with parkland:", nrow(park), "\n")

d <- sc |> left_join(proj, by="nta2020") |> left_join(park, by="nta2020") |>
  mutate(n_projects=ifelse(is.na(n_projects),0,n_projects),
         park_acres=ifelse(is.na(park_acres),0,park_acres),
         got = as.integer(n_projects > 0),
         l_park = log1p(park_acres), l_sub=log1p(subway_riders/1000),
         l_jobs=log1p(jobs/1000), need = resid_ratio,
         need_abs = events_311, boro=factor(boroname))
cat("\noutcome balance: got project =", sum(d$got), " none =", sum(d$got==0), "\n\n")

cat("=== LOGISTIC: P(neighbourhood receives a restroom capital project) ===\n")
f <- got ~ need + l_sub + l_jobs + l_park + poverty_rate + boro
m <- glm(f, family=binomial, data=d)
co <- summary(m)$coefficients
out <- data.frame(term=rownames(co), odds_ratio=round(exp(co[,1]),3),
                  p=round(co[,4],4), row.names=NULL)
print(out[!grepl("Intercept", out$term),], row.names=FALSE)
cat("\nnull deviance", round(m$null.deviance,1), " residual deviance", round(m$deviance,1),
    " McFadden R2 =", round(1-m$deviance/m$null.deviance,3), "\n")

## --- confusion matrix on held-out data (Session 6/7 discipline) ------------
cat("\n=== OUT-OF-SAMPLE CONFUSION MATRIX (70/30, 200 splits averaged) ===\n")
acc <- replicate(200, {
  i <- sample(nrow(d), round(0.7*nrow(d))); tr <- d[i,]; te <- d[-i,]
  fit <- try(glm(f, family=binomial, data=tr), silent=TRUE)
  if(inherits(fit,"try-error")) return(rep(NA,4))
  p <- predict(fit, newdata=te, type="response")
  pred <- as.integer(p > 0.5)
  c(TP=sum(pred==1 & te$got==1), FP=sum(pred==1 & te$got==0),
    FN=sum(pred==0 & te$got==1), TN=sum(pred==0 & te$got==0))
})
a <- rowMeans(acc, na.rm=TRUE)
cat(sprintf("               Predicted: project   Predicted: none\n"))
cat(sprintf("Actual project     %6.1f            %6.1f\n", a["TP"], a["FN"]))
cat(sprintf("Actual none        %6.1f            %6.1f\n", a["FP"], a["TN"]))
cat(sprintf("\naccuracy %.3f   precision %.3f   recall %.3f\n",
            (a["TP"]+a["TN"])/sum(a), a["TP"]/(a["TP"]+a["FP"]), a["TP"]/(a["TP"]+a["FN"])))
base <- max(mean(d$got), 1-mean(d$got))
cat(sprintf("majority-class baseline accuracy: %.3f  <- must beat this\n", base))

## --- the managerial question -----------------------------------------------
cat("\n=== High need but NO investment (the actionable list) ===\n")
print(d |> filter(got==0) |> arrange(desc(need)) |>
  transmute(neighbourhood=substr(ntaname,1,36), unmet_need=round(need,2),
            complaints=events_311, restrooms, park_acres=round(park_acres)) |>
  head(10), row.names=FALSE)
write.csv(d, file.path(D,"model_nta_investment_20260920.csv"), row.names=FALSE)
