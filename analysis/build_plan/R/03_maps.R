# 03_maps.R -- interactive leaflet map (keyless Esri light-grey tiles) + static PNG map.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(data.table); library(ggplot2);
  library(leaflet); library(htmlwidgets)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
PT <- file.path(BASE, "Build_Plan/prototype"); OUT <- file.path(PT, "outputs")
P <- readRDS(file.path(PT, "cache/prep.rds")); R <- readRDS(file.path(PT, "cache/runs.rds"))
cand <- P$cand; sup <- P$sup; cons <- R$cons

# existing restrooms open at 9pm Wednesday (base supply; identical off/in-season, see 02)
op21 <- sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= 21 &
        ifelse(sup$placeholder, 16, sup$w_close) > 21
stopifnot(sum(op21) == R$runs[["residents|base_21_off"]]$n_open)
ex21 <- st_transform(sup[op21, ], 4326)

# consensus sites: every site in a primary run's first 100, with the runs that picked it
lab <- c(residents = "residents", workers = "workers", subway = "subway", streets = "busy streets")
ps <- rbindlist(lapply(names(R$runs)[sub(".*\\|", "", names(R$runs)) %in% R$PRIMARY], function(id) {
  g <- R$runs[[id]]; o <- sub("\\|.*", "", id); h <- if (grepl("14", id)) "2pm" else "9pm"
  data.table(cand_id = cand$cand_id[g$sel[seq_len(min(100, length(g$sel)))]], run = paste(lab[o], h))
}))
site <- ps[, .(n_runs = .N, runs = paste(run, collapse = ", ")), by = cand_id]
site <- merge(site, st_drop_geometry(cand)[, c("cand_id", "type", "lat", "lon", "nta")], by = "cand_id")
nt <- st_drop_geometry(P$nta)[, c("nta2020", "ntaname")]
site$ntaname <- nt$ntaname[match(site$nta, nt$nta2020)]
stopifnot(!anyDuplicated(site$cand_id))
cat("distinct sites in any primary first-100:", nrow(site), "; picked by >=2 runs:", sum(site$n_runs >= 2), "\n")

nta <- P$nta[P$nta$ntatype == "0", ] |> left_join(as.data.frame(cons)[, c("nta", "runs_primary", "sites_primary", "rank")],
                                                   by = c("nta2020" = "nta"))
nta$runs_primary[is.na(nta$runs_primary)] <- 0
nta_ll <- st_transform(st_simplify(nta, dTolerance = 60), 4326)
pil <- st_transform(P$pil, 4326)

# ---- leaflet ---------------------------------------------------------------------------------
pal <- colorNumeric(c("#f7f7f7", "#c6dbef", "#6baed6", "#2171b5", "#08306b"), domain = 0:8)
tiles <- "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"
m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
  addTiles(urlTemplate = tiles, attribution = "Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ",
           options = tileOptions(maxZoom = 16)) |>
  addPolygons(data = nta_ll, fillColor = ~pal(runs_primary), fillOpacity = 0.55, color = "#888", weight = 0.4,
              label = ~sprintf("%s: chosen in %d of 8 runs (%s sites)%s", ntaname, runs_primary,
                               ifelse(is.na(sites_primary), 0, sites_primary),
                               ifelse(is.na(rank), "", paste0(", consensus rank ", rank))),
              group = "Consensus by NTA") |>
  addCircleMarkers(data = ex21, radius = 4, color = "#1a7f37", fillColor = "#2ea043", fillOpacity = 0.9, weight = 1,
                   label = ~paste0(facility_name, " (", operator, ", open 9pm Wed per posted hours)"),
                   group = "Existing restrooms open at 9pm") |>
  addCircleMarkers(data = site, lng = ~lon, lat = ~lat, radius = ~2 + 1.5 * n_runs, color = "#b35806",
                   fillColor = "#f1a340", fillOpacity = 0.8, weight = 1,
                   label = ~sprintf("Candidate %d (%s) in %s: picked by %d of 8 runs", cand_id, type, ntaname, n_runs),
                   popup = ~sprintf("<b>Candidate %d</b> (%s)<br>%s<br>Picked in first 100 by: %s", cand_id, type, ntaname, runs),
                   group = "Greedy sites (first 100, 8 runs)") |>
  addCircleMarkers(data = pil, radius = 7, color = "#6a1b9a", fillColor = "#ab47bc", fillOpacity = 0.95, weight = 2,
                   label = ~paste0("Pilot ", site_id, ": ", published_name), group = "City pilot sites (17)") |>
  addLegend("bottomright", pal = pal, values = 0:8, title = "NTA: runs (of 8)<br>with a first-100 site", opacity = 0.7) |>
  addLegend("bottomleft", colors = c("#2ea043", "#f1a340", "#ab47bc"),
            labels = c(sprintf("Existing restroom open 9pm (%d)", nrow(ex21)), "Greedy site (size = # runs)", "City pilot site (17)"),
            opacity = 0.9) |>
  addLayersControl(overlayGroups = c("Consensus by NTA", "Existing restrooms open at 9pm",
                                     "Greedy sites (first 100, 8 runs)", "City pilot sites (17)"),
                   options = layersControlOptions(collapsed = FALSE)) |>
  setView(-73.94, 40.72, 11)
m$sizingPolicy$defaultHeight <- "100vh"
# pandoc is not installed, so selfcontained = TRUE fails: save with a lib dir, then inline JS/CSS by hand
f_html <- file.path(OUT, "build_plan_map.html"); libdir <- file.path(OUT, "build_plan_map_files")
saveWidget(m, f_html, selfcontained = FALSE, libdir = "build_plan_map_files", title = "NYC restroom build plan prototype")
h <- readLines(f_html, warn = FALSE, encoding = "UTF-8")
inline <- function(line) {
  if (grepl('<script src="build_plan_map_files/', line, fixed = TRUE)) {
    f <- sub('.*<script src="([^"]+)".*', "\\1", line)
    return(c("<script>", readLines(file.path(OUT, f), warn = FALSE, encoding = "UTF-8"), "</script>"))
  }
  if (grepl('<link href="build_plan_map_files/', line, fixed = TRUE)) {
    f <- sub('.*<link href="([^"]+)".*', "\\1", line)
    return(c("<style>", readLines(file.path(OUT, f), warn = FALSE, encoding = "UTF-8"), "</style>"))
  }
  line
}
h2 <- unlist(lapply(h, inline))
stopifnot(!any(grepl("build_plan_map_files/", h2, fixed = TRUE)))
writeLines(h2, f_html, useBytes = TRUE)
unlink(libdir, recursive = TRUE)
stopifnot(!any(grepl("carto", readLines(file.path(OUT, "build_plan_map.html"), warn = FALSE), ignore.case = TRUE)))

# ---- static PNG --------------------------------------------------------------------------------
top_sites <- site[n_runs >= 2]
p <- ggplot() +
  geom_sf(data = nta, aes(fill = runs_primary), colour = "white", linewidth = 0.1) +
  scale_fill_gradientn(colours = c("#f0f0f0", "#c6dbef", "#6baed6", "#2171b5", "#08306b"), limits = c(0, 8),
                       name = "Runs (of 8) giving\nthe NTA a first-100 site") +
  geom_sf(data = st_transform(ex21, 2263), aes(colour = "Existing restroom open 9pm"), size = 1.2) +
  geom_point(data = top_sites, aes(x = st_coordinates(st_transform(st_as_sf(top_sites, coords = c("lon", "lat"), crs = 4326), 2263))[, 1],
                                   y = st_coordinates(st_transform(st_as_sf(top_sites, coords = c("lon", "lat"), crs = 4326), 2263))[, 2],
                                   colour = "Greedy site picked by 2+ runs"), size = 1.1) +
  geom_sf(data = st_transform(pil, 2263), aes(colour = "City pilot site"), shape = 17, size = 2.2) +
  scale_colour_manual(values = c("Existing restroom open 9pm" = "#1a9e3a", "Greedy site picked by 2+ runs" = "#e66101",
                                 "City pilot site" = "#7b1fa2"), name = NULL) +
  labs(title = "Where new restrooms add the most coverage, across objectives and hours",
       subtitle = "Prototype. NTA shade = in how many of 8 greedy runs (4 demand objectives x 2pm/9pm Wed) the NTA gets one of the first 100 sites",
       caption = "500 m straight-line service standard; posted hours; candidates are grid points on Parks land, DOT plazas and busy-street frontage, not verified sites.",
       x = NULL, y = NULL) +
  theme_void(base_size = 9) +
  theme(plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(size = 8.5, colour = "grey30"),
        plot.caption = element_text(size = 7, colour = "grey40", hjust = 0), legend.position = "right",
        plot.background = element_rect(fill = "white", colour = NA))
ggsave(file.path(OUT, "build_plan_map.png"), p, width = 9, height = 8.5, dpi = 150)
cat("maps written\n")
