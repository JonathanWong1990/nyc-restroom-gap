# B1_small_maps.R — small paired maps for the walkthrough: where supply is, and what is
# open at 3pm vs 9pm. Geometry simplified hard to keep the page light.
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"; W <- 460
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> dplyr::select(nta2020)
sc <- read.csv(file.path(D,"model_with_commercial_20260920.csv"))
g0 <- nta |> inner_join(sc |> dplyr::select(nta2020, ntaname), by="nta2020") |>
  st_simplify(dTolerance=620, preserveTopology=TRUE)
bb <- st_bbox(g0); H <- round(W*(bb["ymax"]-bb["ymin"])/(bb["xmax"]-bb["xmin"]))
sx <- function(x)(x-bb["xmin"])/(bb["xmax"]-bb["xmin"])*W
sy <- function(y) H-(y-bb["ymin"])/(bb["ymax"]-bb["ymin"])*H
pathfor <- function(geom){
  cs <- st_coordinates(geom); out <- character(0)
  for(p in unique(cs[,"L2"])) for(r in unique(cs[cs[,"L2"]==p,"L1"])){
    m <- cs[cs[,"L2"]==p & cs[,"L1"]==r, c("X","Y"), drop=FALSE]
    if(nrow(m)<3) next
    out <- c(out, paste0("M", paste(sprintf("%.0f %.0f", sx(m[,1]), sy(m[,2])), collapse="L"), "Z"))
  }
  paste(out, collapse="")
}
paths <- vapply(seq_len(nrow(g0)), function(i) pathfor(st_geometry(g0)[i]), character(1))

emit <- function(vals, brk, file, title){
  b <- cut(vals, brk, labels=FALSE, include.lowest=TRUE); b[is.na(b)] <- 1
  parts <- sprintf('<path d="%s" class="s%d"><title>%s</title></path>',
                   paths, b, gsub("&","and", substr(g0$ntaname,1,40)))
  writeLines(paste0('<svg viewBox="0 0 ',W,' ',H,'" role="img" aria-label="',title,'">',
                    paste(parts, collapse=""), '</svg>'), file.path(D, file))
  cat(sprintf("%-28s %s\n", file, paste(table(b), collapse=" / ")))
}

## --- supply: operational restrooms per neighbourhood -----------------------
rr <- read.csv(file.path(D,"nycrestrooms_i7jb-7jku_20260920.csv"), stringsAsFactors=FALSE)
rr$fid <- seq_len(nrow(rr))
op <- rr |> filter(status=="Operational", !is.na(latitude), !is.na(longitude))
assign_nta <- function(df) st_as_sf(df, coords=c("longitude","latitude"), crs=4326) |>
  st_transform(2263) |> st_join(nta, join=st_within) |> st_drop_geometry()
sup <- assign_nta(op) |> filter(!is.na(nta2020)) |> count(nta2020, name="n")
g0$supply <- sup$n[match(g0$nta2020, sup$nta2020)]; g0$supply[is.na(g0$supply)] <- 0
cat("restrooms per NTA: median", median(g0$supply), " max", max(g0$supply), "\n")
emit(g0$supply, c(-1,0,1,3,5,8,999), "map_supply.svg",
     "Public restrooms per neighbourhood")

## --- unmet need, simplified to match the small maps --------------------------
g0$ratio <- sc$resid_ratio[match(g0$nta2020, sc$nta2020)]
emit(g0$ratio, c(-1, 0.5, 0.8, 1.25, 1.8, 2.5, 99), "map_need_small.svg",
     "Unmet need by neighbourhood")

## --- what is open at 3pm vs 9pm -------------------------------------------
ph <- read.csv(file.path(D,"parsed_hours_20260920.csv"))
boiler <- grepl("Open later seasonally", rr$hours_of_operation, ignore.case=TRUE)
real <- rr$fid[rr$status=="Operational" & !boiler]
openat <- function(h) unique(ph$facility_id[ph$parsed & ph$is_open &
                     ph$facility_id %in% real & ph$open_hour<=h & ph$close_hour>h])
cover <- function(h){
  ids <- openat(h)
  pts <- op |> filter(fid %in% ids)
  if(!nrow(pts)) return(rep(0, nrow(g0)))
  buf <- st_union(st_buffer(st_as_sf(pts, coords=c("longitude","latitude"), crs=4326) |>
                            st_transform(2263), 400/0.3048))
  ii <- suppressWarnings(st_intersection(st_make_valid(g0), buf))
  ii$a <- as.numeric(st_area(ii))
  agg <- ii |> st_drop_geometry() |> group_by(nta2020) |> summarise(a=sum(a), .groups="drop")
  tot <- as.numeric(st_area(g0))
  v <- agg$a[match(g0$nta2020, agg$nta2020)]; v[is.na(v)] <- 0
  100*v/tot
}
c3 <- cover(15); c9 <- cover(21)
cat(sprintf("mean land coverage: 3pm %.1f%%  9pm %.1f%%\n", mean(c3), mean(c9)))
brk <- c(-1, 1, 10, 25, 45, 70, 101)
emit(c3, brk, "map_open_3pm.svg", "Area within a five-minute walk of an open restroom at 3pm")
emit(c9, brk, "map_open_9pm.svg", "Area within a five-minute walk of an open restroom at 9pm")
