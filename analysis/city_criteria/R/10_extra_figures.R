# 10_extra_figures.R -- candidate-site map and the resident evening-coverage curve (reads 01 and 09 outputs).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table); library(ggplot2)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model"); FIG <- file.path(CM, "outputs/fig")
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); X <- readRDS(file.path(CM, "cache/features.rds"))$X
nta <- st_simplify(P$nta, dTolerance = 40, preserveTopology = TRUE)
th <- theme_void(base_size = 11) + theme(plot.title = element_text(face = "bold", size = 17), plot.subtitle = element_text(size = 12, colour = "grey30"),
  plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), legend.position = c(0.01, 0.99), legend.justification = c(0, 1),
  legend.text = element_text(size = 11), legend.title = element_text(size = 11.5, face = "bold"), legend.background = element_rect(fill = alpha("white", 0.85), colour = NA),
  plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 10, 10, 10))
thb <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold", size = 16), plot.subtitle = element_text(size = 12, colour = "grey30"),
  plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
c0 <- X[pilot == 0]; cp <- st_transform(st_as_sf(c0, coords = c("lon", "lat"), crs = 4326), 2263)
cp$t <- factor(c(park = "Parks land", plaza = "DOT pedestrian plaza", busy_street = "Busy-street frontage")[c0$type], levels = c("Parks land", "Busy-street frontage", "DOT pedestrian plaza"))
k <- table(cp$t); levels(cp$t) <- sprintf("%s (%s)", levels(cp$t), format(as.integer(k), big.mark = ","))
p <- ggplot() + geom_sf(data = nta, fill = "#ecebe8", colour = "white", linewidth = 0.15) +
  geom_sf(data = cp[order(cp$t != levels(cp$t)[3]) , ], aes(colour = t), size = 0.5) +
  scale_colour_manual(values = setNames(c("#6aa47a", "#eda100", "#c0392b"), levels(cp$t)), name = sprintf("%s candidate sites", format(nrow(cp), big.mark = ","))) +
  guides(colour = guide_legend(override.aes = list(size = 4))) +
  labs(title = "Candidate sites: where a modular unit could plausibly go",
       subtitle = "Points on a 150 m grid that fall on Parks land, a DOT plaza, or busy-street frontage",
       caption = "Parks properties (NYC Parks), pedestrian plazas (DOT k5k6-6jex), busy streets = DOT pedestrian demand 'Global'/'Regional' segments (fwpa-qxaf).") + th
ggsave(file.path(FIG, "g2c_candidate_sites.png"), p, width = 8.5, height = 9, dpi = 150)

C <- fread(file.path(CM, "outputs/resident_coverage_curves.csv"))[scenario == "9pm, parks close 4pm"]
S0 <- fread(file.path(CM, "outputs/resident_coverage_summary.csv")); S <- S0[scenario == "9pm, parks close 4pm"]; D14 <- S0[scenario == "2pm (daytime)"]$residents_covered_now
C <- rbind(data.table(scenario = C$scenario[1], new_units = 0, residents_covered = S$covered_after_existing), C)
mk <- data.table(n = as.integer(unlist(S[, .(`80%`, `90%`, `95%`, `100%`)])), y = c(.80, .90, .95, 1.00))
p2 <- ggplot(C, aes(new_units, residents_covered)) + geom_line(linewidth = 1.1, colour = "#0b3d91") +
  geom_hline(yintercept = D14, linetype = 2, colour = "grey45") +
  annotate("text", x = max(mk$n), y = D14, label = sprintf("daytime coverage today: %d%%", round(100 * D14)), hjust = 1, vjust = -0.6, size = 3.8, colour = "grey30") +
  geom_point(data = mk, aes(n, y), size = 3, colour = "#c0392b") +
  geom_text(data = mk, aes(n, y, label = sprintf("%d units: %d%%", n, round(100 * y))), hjust = c(-0.15, -0.15, -0.15, 1.1), vjust = c(1.3, 1.3, 1.3, 1.6), size = 4) +
  scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), limits = c(0.66, 1.005)) +
  labs(title = sprintf("Evening coverage for every resident: about %d new units in this scenario", max(mk$n)),
       subtitle = sprintf("Residents with a restroom open within 500 m at 9pm, after existing restrooms are kept open or repaired (%d%%),\nas new units are added where they reach the most residents", round(100 * S$covered_after_existing)),
       x = "New units", y = NULL,
       caption = "Greedy placement at any residential grid point: a modelled scenario, not a proven minimum or a siting plan.\nStraight-line 500 m; residents from Census ACS 2020-24.") + thb
ggsave(file.path(FIG, "g12_resident_coverage.png"), p2, width = 9.5, height = 5.6, dpi = 150)
cat("done\n")
