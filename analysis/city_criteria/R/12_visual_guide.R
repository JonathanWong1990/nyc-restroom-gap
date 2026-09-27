# 12_visual_guide.R -- the method, step by step, on one neighbourhood (Tribeca / Civic Center, Lower Manhattan).
# Same frame for every panel so the steps can be flipped through (site tab "Visual guide", and slides).
# Uses exactly the objects of 01/05 (candidate sites, demand score, supply rule, gap, chosen restrooms and new units).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table); library(ggplot2); library(maptiles); library(terra)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
D <- file.path(BASE, "Restroom_Rebuild/data_raw"); FIG <- file.path(CM, "outputs/fig"); FT <- 0.3048006096; M2FT <- function(m) m / FT
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); G <- readRDS(file.path(CM, "cache/gap.rds"))
X <- readRDS(file.path(CM, "cache/features.rds"))$X; s <- P$sup
cand <- X[pilot == 0]; cs <- st_transform(st_as_sf(cand, coords = c("lon", "lat"), crs = 4326), 2263)
cs$D0 <- G$D0; cs$gap <- G$gap0; cs$cov14 <- G$cov14; cs$cov21 <- G$cov21; cs$type <- cand$type

# ---- window: 2.5 km square centred on the Tribeca / Civic Center new unit -------------------------------------------
New <- st_transform(st_as_sf(G$New, coords = c("lon", "lat"), crs = 4326), 2263)
c0 <- st_coordinates(New[G$New$ntaname == "Tribeca-Civic Center", ][1, ])
H <- M2FT(1250); BB <- c(xmin = c0[1] - H, xmax = c0[1] + H, ymin = c0[2] - H, ymax = c0[2] + H)
box <- st_as_sfc(st_bbox(BB, crs = st_crs(2263)))
inw <- function(g) { xy <- st_coordinates(st_centroid(st_geometry(g))); xy[, 1] > BB["xmin"] & xy[, 1] < BB["xmax"] & xy[, 2] > BB["ymin"] & xy[, 2] < BB["ymax"] }
wide <- st_buffer(box, M2FT(600))
clipw <- function(g) suppressWarnings(st_intersection(st_make_valid(g), wide))

# ---- basemap tiles: Esri World Light Gray (base + street-name reference layer), reprojected to the plotting CRS ----------
tile_annot <- function(provider) {
  bb4 <- st_transform(st_buffer(box, M2FT(200)), 4326)
  r <- get_tiles(bb4, provider = provider, zoom = 16, crop = TRUE, cachedir = file.path(CM, "cache/tiles"))
  r <- terra::project(r, "EPSG:2263", method = "bilinear")
  v <- terra::values(r); v[is.na(v)] <- 0
  a <- if (terra::nlyr(r) >= 4) v[, 4] else rep(255, nrow(v))
  col <- matrix(rgb(v[, 1], v[, 2], v[, 3], pmin(255, pmax(0, a)), maxColorValue = 255), nrow = terra::nrow(r), byrow = TRUE)
  e <- as.vector(terra::ext(r))
  annotation_raster(col, xmin = e["xmin"], xmax = e["xmax"], ymin = e["ymin"], ymax = e["ymax"], interpolate = TRUE)
}
dir.create(file.path(CM, "cache/tiles"), showWarnings = FALSE)
TILE_BASE <- tile_annot("Esri.WorldGrayCanvas")
TILE_REF  <- tile_annot(create_provider(name = "EsriGrayRef", citation = "Esri",
  url = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}"))

# ---- base layers ----------------------------------------------------------------------------------------------------
land <- clipw(st_union(P$nta))
parks <- clipw(readRDS(file.path(D, "parksprops_sf_20260920.rds")) |> st_transform(2263))
plz <- clipw(st_read(file.path(D, "nycdot_k5k6-6jex_plazas_polygon_20260923.geojson"), quiet = TRUE) |> st_transform(2263))
seg <- st_read(file.path(BASE, "Pedestrian_Demand_Test/data/dotpedmob_fwpa-qxaf_20260925_dedup.geojson"), quiet = TRUE) |> st_transform(2263)
seg <- clipw(seg[seg$category %in% c("Global", "Regional"), ])
cw <- cs[inw(cs), ]

# supply objects
op <- function(h) { cl <- ifelse(s$placeholder, 16, s$w_close); s$operational & !s$removed_closed & !s$removed_fail & s$w_ok & !is.na(s$w_open) & s$w_open <= h & cl > h }
broken_listed <- s$operational & (s$removed_closed | s$removed_fail)
sw <- s[inw(s) | lengths(st_is_within_distance(s, box, dist = M2FT(500))) > 0, ]
okw <- function(v) v[inw(s) | lengths(st_is_within_distance(s, box, dist = M2FT(500))) > 0]
o14 <- okw(op(14)); o21 <- okw(op(21)); brk <- okw(broken_listed); lst <- okw(s$operational)
pil <- st_transform(P$pil, 2263); pilw <- pil[lengths(st_is_within_distance(pil, box, dist = M2FT(500))) > 0, ]
Fac <- st_transform(st_as_sf(G$Fac, coords = c("lon", "lat"), crs = 4326), 2263)
Facw <- Fac[lengths(st_is_within_distance(Fac, box, dist = M2FT(500))) > 0, ]
Neww <- New[lengths(st_is_within_distance(New, box, dist = M2FT(500))) > 0, ]
circ <- function(g) st_buffer(st_geometry(g), M2FT(500))

# example point: a gap site with the highest demand near the centre
cw$dc <- as.numeric(st_distance(cw, st_sfc(st_point(c0), crs = 2263)))
ex <- cw[cw$gap, ]; ex <- ex[order(ex$dc > M2FT(500), -ex$D0), ][1, ]
exi <- which(cand$lon == st_coordinates(st_transform(ex, 4326))[1] & TRUE)[1]
exrow <- cand[match(round(st_coordinates(st_transform(ex, 4326))[1], 7), round(cand$lon, 7))]
res_pts <- st_sf(w = P$demand$residents$w, geometry = st_sfc(P$demand_pts$residents, crs = 2263))
sub_pts <- st_sf(w = P$demand$subway$w, geometry = st_sfc(P$demand_pts$subway, crs = 2263))
exc <- circ(ex)
res_in <- res_pts[lengths(st_intersects(res_pts, exc)) > 0, ]; sub_in <- sub_pts[lengths(st_intersects(sub_pts, exc)) > 0 & sub_pts$w > 0, ]
cat("example:", exrow$ntaname, "| residents", round(exrow$residents), "| jobs", round(exrow$jobs), "| subway", exrow$subway,
    "| demand pct", round(100 * ex$D0), "\n")

# ---- drawing helpers ---------------------------------------------------------------------------------------------
COL <- list(water = "#dfe7ee", land = "#f4f2ee", park = "#cfe3c8", plaza = "#e5d8f0", street = "#d9c7a6")
basemap <- function() ggplot() + TILE_BASE +
  geom_sf(data = parks, fill = alpha("#8cc58a", 0.55), colour = NA) + geom_sf(data = plz, fill = alpha("#b48be0", 0.7), colour = NA) +
  geom_sf(data = seg, colour = "#c9a063", linewidth = 1.2) + TILE_REF
frame <- function(p, n, title, sub) {
  p + coord_sf(xlim = BB[c("xmin", "xmax")], ylim = BB[c("ymin", "ymax")], expand = FALSE, datum = NA) +
    labs(title = sprintf("Step %d · %s", n, title), subtitle = sub,
         caption = "Lower Manhattan from Washington Square to City Hall (2.5 km square). Green = parks, lilac = pedestrian plazas,\ntan = busy street blocks. Basemap: Esri World Light Gray (Esri, HERE, Garmin, OpenStreetMap contributors).") +
    theme_void(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 17), plot.subtitle = element_text(size = 12.5, colour = "grey25", lineheight = 1.1),
          plot.caption = element_text(size = 9, colour = "grey45", hjust = 0), legend.position = "bottom", legend.text = element_text(size = 11),
          legend.title = element_blank(), plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 12, 10, 12))
}
sv <- function(p, i) ggsave(file.path(FIG, sprintf("v%d.png", i)), p, width = 8, height = 8.6, dpi = 150)
TYPE <- c(park = "Candidate site: park land", plaza = "Candidate site: plaza", busy_street = "Candidate site: busy street")

# 1 -- the area
sv(frame(basemap(), 1, "The area", "Pins can only go on green (parks), lilac (pedestrian plazas) or tan (the busiest street blocks).\nEverything else (buildings, ordinary streets) is left out."), 1)

# 2 -- candidate sites
p <- basemap() + geom_sf(data = cw, aes(fill = factor(TYPE[type], levels = TYPE)), shape = 21, size = 2.6, colour = "white", stroke = 0.4) +
  scale_fill_manual(values = setNames(c("#3f8f55", "#8a5cc2", "#b0763a"), TYPE))
sv(frame(p, 2, "Candidate sites", sprintf("A pin every 150 m on park land, plazas and busy streets. %d pins in this window.", nrow(cw))), 2)

# 3 -- demand at one point
lab3 <- sprintf("Within 500 m of this pin:\n%s residents\n%s jobs\n%s subway entries a year\n→ demand rank %d of 100 (top third)",
                format(round(exrow$residents, -2), big.mark = ","), format(round(exrow$jobs, -2), big.mark = ","),
                format(round(exrow$subway, -5), big.mark = ","), round(100 * ex$D0))
exy <- st_coordinates(ex)
p <- basemap() + geom_sf(data = cw, colour = "grey55", size = 1.6) +
  geom_sf(data = res_in, aes(size = w), colour = "#6f86b5", alpha = 0.5, show.legend = FALSE) + scale_size_area(max_size = 3) +
  geom_sf(data = sub_in, shape = 22, fill = "#1f3a6e", colour = "white", size = 3.4) +
  geom_sf(data = exc, fill = NA, colour = "#0b3d91", linewidth = 1, linetype = 2) +
  geom_sf(data = ex, shape = 21, fill = "#0b3d91", colour = "white", size = 4.5, stroke = 0.8) +
  annotate("label", x = BB["xmin"] + M2FT(60), y = BB["ymax"] - M2FT(60), label = lab3, hjust = 0, vjust = 1, size = 3.9,
           fill = alpha("white", 0.9))
sv(frame(p, 3, "Demand: what is around one pin", "Draw a 500 m circle (a 7-minute walk) around the pin and count what is inside.\nBlue dots = where residents live; dark squares = subway stations."), 3)

# 4 -- demand at every point
cw$dem <- cut(cw$D0, c(0, 1 / 3, 2 / 3, 1), labels = c("Lower third of demand", "Middle third", "Top third (high demand)"), include.lowest = TRUE)
p <- basemap() + geom_sf(data = cw, aes(fill = dem), shape = 21, size = 2.8, colour = "white", stroke = 0.4) +
  scale_fill_manual(values = c("Lower third of demand" = "#d7dbe3", "Middle third" = "#8ea2c4", "Top third (high demand)" = "#0b3d91"), drop = FALSE)
sv(frame(p, 4, "Demand at every pin", "The same count for every pin, ranked against all 5,814 in the city.\nBusy Lower Manhattan: most pins here are in the top third."), 4)

# 5 -- the restrooms on the list, and the broken ones
rw <- sw; rw$state <- ifelse(brk, "Listed but broken: not counted", ifelse(lst, "Listed public restroom", NA)); rw <- rw[!is.na(rw$state), ]
p <- basemap() + geom_sf(data = cw, colour = "grey60", size = 1.4) +
  geom_sf(data = rw, aes(shape = state, colour = state), size = 3.6, stroke = 1.3) +
  scale_shape_manual(values = c("Listed public restroom" = 15, "Listed but broken: not counted" = 4)) +
  scale_colour_manual(values = c("Listed public restroom" = "#111111", "Listed but broken: not counted" = "#c0392b"))
sv(frame(p, 5, "Supply: the restrooms on the City's list", "Every listed restroom near this area. Crossed out: closed long-term or failing\ninspections, so not counted as supply."), 5)

# 6 -- supply at 2pm
cw$s14 <- factor(ifelse(cw$cov14, "Pin served: a restroom open within 500 m", "Pin not served"), levels = c("Pin served: a restroom open within 500 m", "Pin not served"))
p <- basemap() + geom_sf(data = circ(sw[o14, ]), fill = alpha("#3f8f55", 0.10), colour = alpha("#3f8f55", 0.6), linewidth = 0.5) +
  geom_sf(data = cw, aes(fill = s14), shape = 21, size = 2.6, colour = "white", stroke = 0.4) +
  geom_sf(data = sw[o14, ], shape = 15, size = 3.2, colour = "#111111") +
  scale_fill_manual(values = c("Pin served: a restroom open within 500 m" = "#3f8f55", "Pin not served" = "#c0392b"), drop = FALSE)
sv(frame(p, 6, "Supply at 2pm", sprintf("%d working restrooms open in or near this area, each with a 500 m circle.\nA pin inside any circle is served: %d of %d pins here.", sum(o14), sum(cw$cov14), nrow(cw))), 6)

# 7 -- supply at 9pm
cw$s21 <- factor(ifelse(cw$cov21, "Pin served: a restroom open within 500 m", "Pin not served"), levels = c("Pin served: a restroom open within 500 m", "Pin not served"))
p <- basemap() + geom_sf(data = circ(sw[o14 & !o21, ]), fill = NA, colour = alpha("grey40", 0.45), linewidth = 0.4, linetype = 3) +
  geom_sf(data = circ(sw[o21, ]), fill = alpha("#3f8f55", 0.12), colour = alpha("#3f8f55", 0.7), linewidth = 0.6) +
  geom_sf(data = cw, aes(fill = s21), shape = 21, size = 2.6, colour = "white", stroke = 0.4) +
  geom_sf(data = sw[o14 & !o21, ], shape = 0, size = 3.2, colour = "grey45") + geom_sf(data = sw[o21, ], shape = 15, size = 3.2, colour = "#111111") +
  scale_fill_manual(values = c("Pin served: a restroom open within 500 m" = "#3f8f55", "Pin not served" = "#c0392b"), drop = FALSE)
sv(frame(p, 7, "Supply at 9pm", sprintf("Most restrooms have closed (hollow squares, dotted circles); %d are still open in or near this area.\n%d of %d pins served.", sum(o21), sum(cw$cov21), nrow(cw))), 7)

# 8 -- demand minus supply
cw$g <- factor(ifelse(!cw$gap, "Not a gap: lower demand, or served at 9pm", ifelse(cw$cov14, "Gap: busy, restroom nearby by day but none at 9pm", "Gap: busy, no restroom nearby at any time")),
               levels = c("Gap: busy, restroom nearby by day but none at 9pm", "Gap: busy, no restroom nearby at any time", "Not a gap: lower demand, or served at 9pm"))
p <- basemap() + geom_sf(data = circ(sw[o21, ]), fill = alpha("#3f8f55", 0.10), colour = alpha("#3f8f55", 0.6), linewidth = 0.5) +
  geom_sf(data = circ(pilw), fill = alpha("#3f8f55", 0.10), colour = alpha("#3f8f55", 0.6), linewidth = 0.5, linetype = 2) +
  geom_sf(data = cw, aes(fill = g, shape = g), size = 2.8, colour = "white", stroke = 0.4) +
  geom_sf(data = pilw, shape = 24, size = 3.6, fill = "white", colour = "#111111", stroke = 0.9) +
  scale_fill_manual(values = c("Gap: busy, restroom nearby by day but none at 9pm" = "#eda100", "Gap: busy, no restroom nearby at any time" = "#c0392b",
                               "Not a gap: lower demand, or served at 9pm" = "#d4d4d0"), drop = FALSE) +
  scale_shape_manual(values = c("Gap: busy, restroom nearby by day but none at 9pm" = 21, "Gap: busy, no restroom nearby at any time" = 22,
                                "Not a gap: lower demand, or served at 9pm" = 21), drop = FALSE) +
  guides(fill = guide_legend(ncol = 1), shape = guide_legend(ncol = 1))
sv(frame(p, 8, "Demand minus supply: the gap", sprintf("Keep the busy pins (top third) with no restroom open at 9pm. %d gap pins here.\nTriangle = a City pilot unit (open to 10pm), which counts as supply.", sum(cw$gap))), 8)

# 9 -- closing the gap
A <- c("Keep park restroom open to 10pm", "Extend other operator's hours", "Repair or reopen")
Facw$a <- factor(c("Existing park restroom kept open to 10pm", "Other operator's restroom open to 10pm", "Repaired, then open to 10pm")[match(Facw$action, A)],
                 levels = c("Existing park restroom kept open to 10pm", "Other operator's restroom open to 10pm", "Repaired, then open to 10pm", "New modular unit"))
nw <- st_sf(a = factor(rep("New modular unit", nrow(Neww)), levels = levels(Facw$a)), geometry = st_geometry(Neww))
allf <- rbind(st_sf(a = Facw$a, geometry = st_geometry(Facw)), nw)
covered_now <- lengths(st_is_within_distance(cw, st_union(c(st_geometry(allf), st_geometry(sw[o21, ]), st_geometry(pilw))), dist = M2FT(500))) > 0
cw$after <- factor(ifelse(cw$gap & covered_now, "Gap pin now covered", ifelse(cw$gap, "Gap pin still open", "Not a gap")), levels = c("Gap pin now covered", "Gap pin still open", "Not a gap"))
p <- basemap() + geom_sf(data = circ(allf), fill = alpha("#0b3d91", 0.08), colour = alpha("#0b3d91", 0.55), linewidth = 0.5) +
  geom_sf(data = cw, aes(colour = after), size = 1.9) +
  geom_sf(data = allf, aes(fill = a, shape = a), size = 4.2, colour = "white", stroke = 0.6) +
  scale_colour_manual(values = c("Gap pin now covered" = "#6f86b5", "Gap pin still open" = "#c0392b", "Not a gap" = "#d4d4d0"), drop = FALSE, guide = "none") +
  scale_fill_manual(values = c("Existing park restroom kept open to 10pm" = "#eda100", "Other operator's restroom open to 10pm" = "#4a3aa7",
                               "Repaired, then open to 10pm" = "#2a78d6", "New modular unit" = "#c0392b"), drop = TRUE) +
  scale_shape_manual(values = c("Existing park restroom kept open to 10pm" = 21, "Other operator's restroom open to 10pm" = 22,
                                "Repaired, then open to 10pm" = 24, "New modular unit" = 23), drop = TRUE) +
  guides(fill = guide_legend(ncol = 2), shape = guide_legend(ncol = 2))
sv(frame(p, 9, "Closing the gap", sprintf("First existing restrooms, kept open or repaired; then a new unit where none can reach.\nEvery gap pin here ends up within 500 m of an open restroom (%d of %d).", sum(cw$gap & covered_now), sum(cw$gap))), 9)
cat("window: pins", nrow(cw), "| gap", sum(cw$gap), "| covered after", sum(cw$gap & covered_now), "| open14", sum(o14), "| open21", sum(o21), "| broken", sum(brk),
    "| fac", nrow(Facw), "| new", nrow(Neww), "| pilots", nrow(pilw), "\n")
