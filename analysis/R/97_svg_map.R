# 97_svg_map.R — render the unmet-need choropleth as inline SVG for the write-up.
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"
sc <- read.csv(file.path(D,"model_with_commercial_20260920.csv"))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> dplyr::select(nta2020)
g <- nta |> inner_join(sc |> dplyr::select(nta2020, ntaname, resid_ratio, events_311, restrooms),
                       by="nta2020") |>
  st_simplify(dTolerance=260, preserveTopology=TRUE)
bb <- st_bbox(g); W <- 900
H <- round(W * (bb["ymax"]-bb["ymin"]) / (bb["xmax"]-bb["xmin"]))
sx <- function(x) (x-bb["xmin"])/(bb["xmax"]-bb["xmin"])*W
sy <- function(y) H - (y-bb["ymin"])/(bb["ymax"]-bb["ymin"])*H

pathfor <- function(geom){
  cs <- st_coordinates(geom); out <- character(0)
  for(p in unique(cs[,"L2"])){
    for(r in unique(cs[cs[,"L2"]==p,"L1"])){
      m <- cs[cs[,"L2"]==p & cs[,"L1"]==r, c("X","Y"), drop=FALSE]
      if(nrow(m)<3) next
      out <- c(out, paste0("M", paste(sprintf("%.1f %.1f", sx(m[,1]), sy(m[,2])), collapse="L"), "Z"))
    }
  }
  paste(out, collapse="")
}
# The value has a meaningful midpoint: 1.0 = exactly as many complaints as expected.
# So this is a DIVERGING scale - below expectation / about as expected / above expectation -
# not a light-to-dark ramp, which would hide where the dividing line falls.
# Everything at or below expectation reads as one flat neutral: the distinction between
# 0.4x and 0.9x is not actionable. Only the above-expectation range is ramped.
brk <- c(-Inf, 1.25, 1.8, 2.5, Inf)
lab <- c("at or below expected","above expected","well above","far above")
g$bin <- cut(g$resid_ratio, brk, labels=lab)
cat("bin counts:\n"); print(table(g$bin))

parts <- character(nrow(g))
for(i in seq_len(nrow(g))){
  ttl <- sprintf("%s — %d complaints, %.2fx expected, %d restrooms",
                 g$ntaname[i], g$events_311[i], g$resid_ratio[i], g$restrooms[i])
  parts[i] <- sprintf('<path d="%s" class="b%d"><title>%s</title></path>',
    pathfor(st_geometry(g)[i]), as.integer(g$bin[i]),
    gsub("&","and", gsub("<|>","", ttl)))
}
svg <- paste0('<svg viewBox="0 0 ', W, ' ', H, '" role="img" aria-label="Choropleth of New York City neighbourhoods shaded by unmet restroom need, the ratio of observed to model-predicted complaints. The darkest areas are Brighton Beach, East Elmhurst, East Flatbush and East Harlem North." xmlns="http://www.w3.org/2000/svg">',
  paste(parts, collapse=""), '</svg>')
writeLines(svg, file.path(D,"map_unmet_need.svg"))
cat("\nSVG written:", round(file.size(file.path(D,"map_unmet_need.svg"))/1024), "KB,",
    W, "x", H, "\n")
