# 06_layer_steps.R -- one map per walkthrough layer (steps 1-4), building up to diagnosis_map_final.png.
# Same base map, palette and rule as 04_maps_final.R / 03_final_rule.R; each step colours what that layer decides.
# Reads Build_Plan/layered/cache/layers_final.rds and Build_Plan/prototype/cache/prep.rds (read-only).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(ggplot2)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
LY <- file.path(BASE, "Build_Plan/layered"); OUT <- file.path(LY, "outputs")
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); L <- readRDS(file.path(LY, "cache/layers_final.rds"))$L
nta_all <- st_simplify(P$nta, dTolerance = 40, preserveTopology = TRUE)
res <- nta_all[nta_all$ntatype == "0", ] |> left_join(as.data.frame(L)[, setdiff(names(L), c("ntaname", "boroname"))], by = "nta2020")
stopifnot(nrow(res) == 197, sum(res$in_29) == 29)
GAP <- 0.40; REC <- 0.5                                   # thresholds of 03_final_rule.R
res$day_gap <- res$L2_residents >= GAP
res$eve_cls <- res$L3_residents >= GAP & !res$day_gap
res$eve_ext <- res$eve_cls & res$L3_ext_recov_frac >= REC
d29 <- res[res$in_29, ]; six <- res[res$confident_six %in% TRUE, ]

# categories per step (29 only); colours match 04_maps_final.R
d29$s3 <- ifelse(d29$day_gap, "day", ifelse(d29$eve_ext, "ext", ifelse(d29$eve_cls, "else", "none")))
n <- table(factor(d29$s3, levels = c("day", "ext", "else", "none"))); print(n)
stopifnot(n[["day"]] == 13, sum(d29$final_fix) == 3, n[["else"]] == 1)
n_day_all <- sum(res$day_gap, na.rm = TRUE); stopifnot(n_day_all == 77)

centroid_lab <- function(d, txt, dy = 3500) {
  xy <- st_coordinates(suppressWarnings(st_point_on_surface(st_geometry(d))))
  data.frame(x = xy[, 1], y = xy[, 2] + dy, label = txt)
}
th <- theme_void(base_size = 9) +
  theme(plot.title = element_text(face = "bold", size = 16), plot.subtitle = element_text(size = 11.5, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), legend.position = c(0.01, 0.99),
        legend.justification = c(0, 1), legend.text = element_text(size = 11), legend.title = element_text(size = 11.5, face = "bold"),
        legend.key.size = unit(0.55, "cm"), legend.key.spacing.y = unit(0.15, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.85), colour = NA),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(8, 8, 8, 8))
base <- function() ggplot() + geom_sf(data = nta_all, fill = "#e9e9e7", colour = "white", linewidth = 0.15)
lbl <- function(df) geom_label(data = df, aes(x = x, y = y, label = label), size = 3.2, linewidth = 0, fill = alpha("white", 0.85),
                               label.padding = unit(0.08, "lines"), colour = "#111111")
save <- function(p, f) ggsave(file.path(OUT, f), p, width = 8.5, height = 9, dpi = 150)
CAP <- "Grey = not one of the 29. Weekday, posted hours, 500 m straight line to a listed restroom."

# ---- step 1: the screen ------------------------------------------------------------------------------
d29$s1 <- ifelse(d29$confident_six %in% TRUE, "Clearest cases (6): 95% likely above 1.5x", "Other high-complaint areas (23)")
p1 <- base() +
  geom_sf(data = res[!res$in_29, ], fill = "#f4f4f2", colour = "white", linewidth = 0.15) +
  geom_sf(data = d29, aes(fill = s1), colour = "white", linewidth = 0.25) +
  scale_fill_manual(values = c("Clearest cases (6): 95% likely above 1.5x" = "#1f2d3d", "Other high-complaint areas (23)" = "#8a9bb0"),
                    name = "Complaints at least 1.5x\nwhat crowds predict (29)") +
  lbl(transform(centroid_lab(six, six$ntaname), x = x + ifelse(grepl("^Midtown", label), -9000, ifelse(grepl("^East Elm", label), 6000, 0)),
                y = y + ifelse(grepl("^Astoria", label), -9000, ifelse(grepl("^East Elm", label), 1500, 0)))) +
  labs(title = "Layer 1: the 29 neighbourhoods to examine",
       subtitle = "Complaints screen where to look. The next three layers ask what kind of gap each has.", caption = CAP) + th
save(p1, "step1_screen.png")

# ---- step 2: daytime gap -----------------------------------------------------------------------------
d29$s2 <- ifelse(d29$day_gap, "Daytime gap (13): 40%+ of residents\nhave no restroom open at 2pm",
                 "Covered by day (16): go to Layer 3")
p2 <- base() +
  geom_sf(data = res[!res$in_29 & res$day_gap %in% TRUE, ], aes(fill = "Daytime gap outside the 29 (64):\nno complaint signal, not examined"),
          colour = "white", linewidth = 0.15) +
  geom_sf(data = d29, aes(fill = s2), colour = "white", linewidth = 0.25) +
  geom_sf(data = d29, fill = NA, colour = "#333333", linewidth = 0.3) +
  scale_fill_manual(values = c("Daytime gap (13): 40%+ of residents\nhave no restroom open at 2pm" = "#c0392b",
                               "Covered by day (16): go to Layer 3" = "#cfd6de",
                               "Daytime gap outside the 29 (64):\nno complaint signal, not examined" = "#f3d3cf"),
                    breaks = c("Daytime gap (13): 40%+ of residents\nhave no restroom open at 2pm", "Covered by day (16): go to Layer 3",
                               "Daytime gap outside the 29 (64):\nno complaint signal, not examined"), name = "The 29, at 2pm") +
  labs(title = "Layer 2: where there is no restroom nearby even by day",
       subtitle = "Rule: 40% or more of residents have no restroom open within 500 m at 2pm.\nNothing is open to extend, so these point to new sites (unless repair closes the gap: Layer 4).",
       caption = CAP) + th
save(p2, "step2_daytime.png")

# ---- step 3: evening gap -----------------------------------------------------------------------------
K3 <- c(day = "Daytime gap (13), from Layer 2", ext = sprintf("Covered by day, not at 9pm; longer park\nhours would close most of the gap (%d)", n[["ext"]]),
        "else" = "Covered by day, not at 9pm; longer park\nhours would NOT close it (1)", none = "No large gap by day or at 9pm")
COL3 <- c("#f0c9c4", "#eda100", "#4a3aa7", "#cfd6de"); names(COL3) <- K3
d29$s3f <- factor(K3[d29$s3], levels = K3[n[names(K3)] > 0])
p3 <- base() +
  geom_sf(data = d29, aes(fill = s3f), colour = "white", linewidth = 0.25) +
  geom_sf(data = d29, fill = NA, colour = "#333333", linewidth = 0.3) +
  scale_fill_manual(values = COL3, name = "The 29, at 9pm") +
  lbl(centroid_lab(d29[d29$s3 == "else", ], "Midtown–Times Square")) +
  labs(title = "Layer 3: where restrooms exist but are shut at night",
       subtitle = "Rule: covered by day, but 40%+ of residents have no restroom open at 9pm,\nand keeping park restrooms open to 10pm would recover at least half of that gap.",
       caption = paste(CAP, "\nPark restrooms on standard hours are assumed to close at 4pm; the scenario keeps them open to 10pm.",
                       "\nTwo of the 15 (East Harlem North, Corona) move to repair in Layer 4, leaving 13 longer-hours areas.")) + th
save(p3, "step3_evening.png")

# ---- step 4: repair ----------------------------------------------------------------------------------
fx <- d29[d29$final_fix, ]
s4 <- ifelse(d29$final_fix, "fix", d29$s3); m <- table(factor(s4, levels = c("fix", "day", "ext", "else")))
stopifnot(m[["fix"]] == 3, m[["day"]] == 12, m[["ext"]] == 13, m[["else"]] == 1)
K4 <- c(fix = "Repair or reopen (3): restores 10+\npoints of coverage",
        day = "Daytime gap remains (12): new sites\n(Brighton Beach left this group)",
        ext = "Longer-hours areas (13)", "else" = "Assess separately (1): Midtown")
COL4 <- setNames(c("#2a78d6", alpha(COL3[1:3], 0.45)), K4)
d29$s4 <- factor(K4[s4], levels = K4)
p4 <- base() +
  geom_sf(data = d29, aes(fill = s4), colour = "white", linewidth = 0.25) +
  geom_sf(data = d29, fill = NA, colour = "#333333", linewidth = 0.3) +
  scale_fill_manual(values = COL4, name = "The 29, after Layer 4") +
  lbl(centroid_lab(fx, sprintf("%s: +%.0f pts", fx$ntaname, fx$fix_gain_pp))) +
  labs(title = "Layer 4: where repairing what exists comes first",
       subtitle = "Rule: restrooms that are long-term closed or repeatedly failing inspection serve 10+ points\nof residents' coverage. Repair is checked first because it uses restrooms that already exist.",
       caption = paste(CAP, "\nPoints = percentage points of residents with a restroom within 500 m at 2pm. Repeated failure is treated as unusable (a scenario).")) + th
save(p4, "step4_repair.png")
cat("step maps written\n")
