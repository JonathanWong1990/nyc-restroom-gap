# 04_maps_final.R -- same as 02_maps.R but using the cost-ordered final rule (03_final_rule.R).
# 02_maps.R -- diagnosis_map.png, layers_4panel.png, diagnosis_map.html (keyless Esri tiles, inlined deps).
# Reads Build_Plan/layered/cache/layers.rds (01_layers.R) and Build_Plan/prototype/cache/prep.rds (read-only).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(data.table); library(ggplot2); library(patchwork);
  library(leaflet); library(htmlwidgets)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
LY <- file.path(BASE, "Build_Plan/layered"); OUT <- file.path(LY, "outputs")
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); X <- readRDS(file.path(LY, "cache/layers_final.rds")); X$L$primary_action <- X$L$final_action
X$L$primary_action <- X$L$display_action   # BUILD split and LOOK ELSEWHERE label come from 03_final_rule.R
# final-rule flags, build lines only for final BUILD areas, pilot labels from the final rule (number-check fixes)
X$L$flags <- trimws(paste0(ifelse(X$L$final_fix, "FIX ", ""), ifelse(X$L$final_build, "BUILD ", ""), ifelse(X$L$final_extend, "EXTEND HOURS", "")))
X$L$flags[X$L$flags == ""] <- "none"
X$L$build_sites_needed[X$L$final_action != "BUILD"] <- NA
X$bs <- X$bs[X$bs$ntaname %in% X$L$ntaname[X$L$final_action == "BUILD"], ]
X$pl$primary_action <- X$L$final_action[match(X$pl$nta2020, X$L$nta2020)]; X$pl$flags <- X$L$flags[match(X$pl$nta2020, X$L$nta2020)]
data.table::fwrite(X$pl, file.path(LY, "outputs/pilot_in_29_final.csv"))
L <- X$L; bs <- X$bs; pl <- X$pl
nta_all <- st_simplify(P$nta, dTolerance = 40, preserveTopology = TRUE)
res <- nta_all[nta_all$ntatype == "0", ] |> left_join(as.data.frame(L)[, setdiff(names(L), c("ntaname", "boroname"))], by = "nta2020")
stopifnot(nrow(res) == 197, sum(res$in_29) == 29)
d29 <- res[res$in_29, ]; six <- res[res$confident_six %in% TRUE, ]
stopifnot(nrow(six) == 6)
pil <- st_as_sf(pl, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(2263)

# colour-blind-safe categorical set, validated all-pairs (dataviz validate_palette.js --pairs all: CVD dE >= 13, normal >= 16)
ACT <- c("BUILD" = "#c0392b", "BUILD, VERIFY FIRST" = "#eba99f", "FIX" = "#2a78d6", "EXTEND HOURS" = "#eda100", "LOOK ELSEWHERE" = "#4a3aa7")
DESC <- c("BUILD" = "Build: daytime gap,\nstronger complaint signal",
          "BUILD, VERIFY FIRST" = "Build, verify first: daytime gap,\nweaker complaint signal",
          "FIX" = "Fix: repair or reopening restores\n10+ points of coverage",
          "EXTEND HOURS" = "Extend hours: covered by day,\nnot at 9pm",
          "LOOK ELSEWHERE" = "Look elsewhere: evening gap that\nlonger park hours would not close")
cnt <- table(factor(d29$primary_action, levels = names(ACT)))
lab <- setNames(sprintf("%s (%d)", DESC, cnt), names(ACT))
d29$primary_action <- factor(d29$primary_action, levels = names(ACT))

# ---- (a) diagnosis_map.png ----------------------------------------------------------------------
lab_six <- st_drop_geometry(six)[, "ntaname", drop = FALSE]; xy <- st_coordinates(suppressWarnings(st_point_on_surface(st_geometry(six))))
lab_six$x <- xy[, 1]; lab_six$y <- xy[, 2] + ifelse(grepl("^Astoria", lab_six$ntaname), -5500, 3500)
p <- ggplot() +
  geom_sf(data = nta_all, fill = "#e9e9e7", colour = "white", linewidth = 0.15) +
  geom_sf(data = d29, aes(fill = primary_action), colour = "white", linewidth = 0.25) +
  geom_sf(data = six, fill = NA, colour = "black", linewidth = 0.7) +
  geom_sf(data = pil, aes(shape = "City pilot site (17)"), size = 2.4, colour = "#222222", fill = "white", stroke = 0.5) +
  geom_label(data = lab_six, aes(x = x, y = y, label = ntaname), size = 3.1, linewidth = 0, fill = alpha("white", 0.8),
                label.padding = unit(0.08, "lines"), colour = "#111111") +
  scale_fill_manual(values = ACT, labels = lab, drop = FALSE, name = "The 29 neighbourhoods with\ncomplaints >= 1.5x expected") +
  scale_shape_manual(values = c("City pilot site (17)" = 24), name = NULL) +
  guides(fill = guide_legend(order = 1, override.aes = list(colour = NA)), shape = guide_legend(order = 2)) +
  labs(title = "The 29 high-complaint neighbourhoods:\nwhich access gap each has, and what to check first",
       subtitle = "Black outline = the six with a 95%-certain complaint excess.\nBuild is split at the natural break in complaint-signal strength.",
       caption = paste("Wednesday, posted hours, 500 m straight line to a listed-operational restroom (register dated June 2025).",
                       "\nOrder: fix what exists, then build, then extend hours. Complaints are a screen, not proof of need.")) +
  theme_void(base_size = 9) +
  theme(plot.title = element_text(face = "bold", size = 17), plot.subtitle = element_text(size = 12, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), legend.position = c(0.01, 0.99),
        legend.justification = c(0, 1), legend.text = element_text(size = 11.5), legend.title = element_text(size = 12, face = "bold"),
        legend.key.size = unit(0.55, "cm"), legend.key.spacing.y = unit(0.18, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.85), colour = NA),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(8, 8, 8, 8))
ggsave(file.path(OUT, "diagnosis_map_final.png"), p, width = 9, height = 9.5, dpi = 160)

# ---- (b) layers_4panel.png ----------------------------------------------------------------------
base_map <- function(fill_scale, var, title, sub) {
  ggplot() +
    geom_sf(data = nta_all, fill = "#f2f2f0", colour = "white", linewidth = 0.1) +
    geom_sf(data = res, aes(fill = .data[[var]]), colour = "white", linewidth = 0.1) +
    geom_sf(data = d29, fill = NA, colour = "black", linewidth = 0.3) +
    fill_scale + labs(title = title, subtitle = sub) +
    theme_void(base_size = 8) +
    theme(plot.title = element_text(face = "bold", size = 10), plot.subtitle = element_text(size = 7, colour = "grey30"),
          legend.position = c(0.03, 0.97), legend.justification = c(0, 1), legend.key.height = unit(0.35, "cm"),
          legend.key.width = unit(0.3, "cm"), legend.title = element_text(size = 7), legend.text = element_text(size = 6.5))
}
res$log_ratio <- log2(pmax(res$resid_ratio, 0.25))   # 0 complaints -> floor at 0.25x (squished anyway)
pct <- function(x) paste0(round(100 * x), "%")
seqs <- function(name, lim = c(0, 1), lab = pct) scale_fill_gradient(low = "#eef3fb", high = "#0b3d91", limits = lim, labels = lab, name = name, na.value = "#f2f2f0")
p1 <- base_map(scale_fill_gradient2(low = "#2a78d6", mid = "#e6e6e3", high = "#c0392b", midpoint = 0, limits = c(-2, 2), oob = scales::squish,
                                    breaks = log2(c(0.25, 0.5, 1, 2, 4)), labels = c("0.25x", "0.5x", "1x", "2x", "4x"), name = "Observed ÷\nexpected"),
               "log_ratio", "1  Problem: complaints vs expected", "311 complaint model residual ratio; black outline = the 29 (>= 1.5x)")
p2 <- base_map(seqs("Residents"), "L2_residents", "2  Missing: no restroom even by day", "Share of residents with no restroom open within 500 m at 2pm")
p3 <- base_map(seqs("Residents"), "L3_residents", "3  Closed: covered by day, not at 9pm", "Share of residents covered at 2pm but not at 9pm (off-season)")
p4 <- base_map(scale_fill_gradient(low = "#eef3fb", high = "#0b3d91", limits = c(0, 25), oob = scales::squish, name = "pct points",
                                   labels = function(x) ifelse(x >= 25, "25+", x)),
               "L4_lost_pp", "4  Broken: coverage resting on broken restrooms", "Resident 2pm coverage lost if long-term-closed / failing Parks restrooms removed")
p4p <- (p1 | p2) / (p3 | p4) + plot_annotation(
  title = "Four layers: where complaints are high, and which access gaps coincide",
  caption = "197 residential NTAs (2020). Wednesday, posted hours, 500 m straight line. Grey = non-residential NTA. Black outline = the 29 high-complaint NTAs.",
  theme = theme(plot.title = element_text(face = "bold", size = 13), plot.caption = element_text(size = 7, colour = "grey40", hjust = 0),
                plot.background = element_rect(fill = "white", colour = NA)))
ggsave(file.path(OUT, "layers_4panel_final.png"), p4p, width = 11, height = 11, dpi = 150)

# ---- (c) diagnosis_map.html -----------------------------------------------------------------------
f1 <- function(x) ifelse(is.na(x), "n/a", sprintf("%.0f%%", 100 * x))
res_ll <- st_transform(res, 4326)
res_ll$popup <- with(res_ll, sprintf(paste0(
  "<b>%s</b> (%s)<br>%s",
  "<br><b>1 Problem</b>: %d complaints vs %.1f expected, ratio %.2f%s",
  "<br><b>2 Missing</b> (no restroom within 500 m at 2pm): residents %s; busy-street length %s; subway entries %s",
  "<br><b>3 Closed</b> (covered 2pm, not 9pm): residents %s; recovered if placeholder park hours ran to 10pm: %s of that gap",
  "<br><b>4 Broken</b>: %d Parks restrooms serve it; long-term closed %d; repeatedly failing %d; largest share of residents served by one broken restroom %s; 2pm coverage lost if removed %.1f pts; PIP 2026 Jan-Jun failure rate %s (n=%d rated inspections)",
  "%s",
  "<br><b>Flags</b>: %s &nbsp; <b>Primary action: %s</b>%s"),
  ntaname, boroname, ifelse(in_29, "<i>One of the 29 high-complaint NTAs</i>", "Not in the 29"),
  events_311, pred, resid_ratio, ifelse(confident_six %in% TRUE, " &mdash; <b>confident six</b>", ""),
  f1(L2_residents), f1(L2_streets), f1(L2_subway), f1(L3_residents), f1(L3_ext_recov_frac),
  as.integer(parks_restrooms_serving), as.integer(n_long_term_closed), as.integer(n_repeatedly_failing), f1(max_res_share_one_broken), L4_lost_pp,
  f1(pip26_fail_rate), as.integer(pip26_n_rated),
  ifelse(nzchar(broken_names), paste0("<br><small>", broken_names, "</small>"), ""),
  flags, primary_action,
  ifelse(!is.na(build_sites_needed), sprintf("<br>Build: %d prototype site(s) bring Layer 2 to %s%s",
         as.integer(build_sites_needed), f1(build_L2_after), ifelse(build_target_reached %in% TRUE, "", " (target 40% NOT reached with prototype candidates)")), "")))
res_ll$fillc <- ifelse(res_ll$in_29, ACT[as.character(res_ll$primary_action)], "#d9d9d6")
tiles <- "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"
bA <- bs[grepl("^prototype", candidate_set)]; bB <- bs[!grepl("^prototype", candidate_set)]
pil_ll <- st_transform(pil, 4326)
m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
  addTiles(urlTemplate = tiles, attribution = "Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ", options = tileOptions(maxZoom = 16)) |>
  addPolygons(data = res_ll[!res_ll$in_29, ], fillColor = ~fillc, fillOpacity = 0.35, color = "#999", weight = 0.4,
              popup = ~popup, label = ~ntaname, group = "Other residential NTAs") |>
  addPolygons(data = res_ll[res_ll$in_29, ], fillColor = ~fillc, fillOpacity = 0.7,
              color = ~ifelse(confident_six %in% TRUE, "#000000", "#ffffff"), weight = ~ifelse(confident_six %in% TRUE, 2.5, 1),
              popup = ~popup, label = ~sprintf("%s: %s", ntaname, primary_action), group = "The 29 high-complaint NTAs") |>
  addCircleMarkers(data = bA, lng = ~lon, lat = ~lat, radius = 5, color = "#111", fillColor = "#ffffff", fillOpacity = 1, weight = 2,
                   label = ~sprintf("Build site #%d for %s (%s)", rank, ntaname, cand_type),
                   popup = ~sprintf("<b>Build site #%d for %s</b><br>Candidate %d, %s<br>New residents covered: %s<br>Layer 2 after: %s",
                                    rank, ntaname, cand_id, cand_type, format(new_residents_covered, big.mark = ","), f1(L2_after)),
                   group = "Build sites (prototype candidates)") |>
  addCircleMarkers(data = bB, lng = ~lon, lat = ~lat, radius = 4, color = "#555", fillColor = "#bbbbbb", fillOpacity = 1, weight = 1,
                   label = ~sprintf("Diagnostic any-location site #%d for %s (unverified street point)", rank, ntaname),
                   group = "Build sites (any-location diagnostic)") |>
  addCircleMarkers(data = pil_ll, radius = 6, color = "#ffffff", fillColor = "#111111", fillOpacity = 1, weight = 2, label = ~sprintf("Pilot %s: %s (%s, %s)", site_id, published_name, ntaname, primary_action),
             group = "City pilot sites (17)") |>
  addControl(html = paste0("<div style='font:14px/1.35 system-ui,sans-serif;max-width:320px'><b>The 29 high-complaint neighbourhoods</b><br>",
                           "Click an area for every layer's value. Toggle build sites and pilot sites top right.<br>",
                           "<a href='../index.html#map'>&larr; Back to the walkthrough</a></div>"), position = "topleft") |>
  addLegend("bottomright", colors = unname(ACT), labels = gsub("\\n", " ", unname(lab)), title = "The 29: primary action", opacity = 0.8) |>
  addLayersControl(overlayGroups = c("The 29 high-complaint NTAs", "Other residential NTAs", "Build sites (prototype candidates)",
                                     "Build sites (any-location diagnostic)", "City pilot sites (17)"),
                   options = layersControlOptions(collapsed = FALSE)) |>
  hideGroup("Build sites (any-location diagnostic)") |>
  setView(-73.94, 40.70, 11)
m$sizingPolicy$defaultHeight <- "100vh"
f_html <- file.path(OUT, "diagnosis_map_final.html"); libdir <- file.path(OUT, "diagnosis_map_final_files")
if (rmarkdown::pandoc_available()) {
  saveWidget(m, f_html, selfcontained = TRUE, title = "Layered diagnosis")
} else {                 # pandoc absent: save with a lib dir, then inline JS/CSS by hand (as the prototype did)
  saveWidget(m, f_html, selfcontained = FALSE, libdir = "diagnosis_map_final_files", title = "Layered diagnosis")
  h <- readLines(f_html, warn = FALSE, encoding = "UTF-8")
  inline <- function(line) {
    if (grepl('<script src="diagnosis_map_final_files/', line, fixed = TRUE)) {
      f <- sub('.*<script src="([^"]+)".*', "\\1", line)
      return(c("<script>", readLines(file.path(OUT, f), warn = FALSE, encoding = "UTF-8"), "</script>"))
    }
    if (grepl('<link href="diagnosis_map_final_files/', line, fixed = TRUE)) {
      f <- sub('.*<link href="([^"]+)".*', "\\1", line)
      return(c("<style>", readLines(file.path(OUT, f), warn = FALSE, encoding = "UTF-8"), "</style>"))
    }
    line
  }
  h2 <- unlist(lapply(h, inline))
  stopifnot(!any(grepl("diagnosis_map_final_files/", h2, fixed = TRUE)))
  writeLines(h2, f_html, useBytes = TRUE)
  unlink(libdir, recursive = TRUE)
}
stopifnot(!any(grepl("carto", readLines(f_html, warn = FALSE), ignore.case = TRUE)))
cat("maps written; html MB:", round(file.size(f_html) / 1e6, 2), "\n")
