# 06_gap_figures.R -- figures for the demand-minus-supply walkthrough (reads cache/gap.rds from 05_gap.R).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table); library(ggplot2); library(logistf); library(patchwork)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FIG <- file.path(CM, "outputs/fig"); FT <- 0.3048006096
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); G <- readRDS(file.path(CM, "cache/gap.rds"))
F0 <- readRDS(file.path(CM, "cache/features.rds")); X <- F0$X; cand <- X[pilot == 0]
D29 <- fread(file.path(BASE, "Build_Plan/layered/outputs/diagnosis_29_final.csv"))
nta <- st_simplify(P$nta, dTolerance = 40, preserveTopology = TRUE)
th <- theme_void(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 17), plot.subtitle = element_text(size = 12, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), legend.position = c(0.01, 0.99),
        legend.justification = c(0, 1), legend.text = element_text(size = 11), legend.title = element_text(size = 11.5, face = "bold"),
        legend.background = element_rect(fill = alpha("white", 0.85), colour = NA),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 10, 10, 10))
thb <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold", size = 16), plot.subtitle = element_text(size = 12, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
base <- function() ggplot() + geom_sf(data = nta, fill = "#ecebe8", colour = "white", linewidth = 0.15)
pts <- function(d) st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), 2263)
save <- function(p, f, w = 8.5, h = 9) ggsave(file.path(FIG, f), p, width = w, height = h, dpi = 150)
cp <- pts(cand); pil <- pts(X[pilot == 1])

# g3 -- the pilot model
M <- copy(G$M7)[term %in% c("busy", "z_d2", "z_d9", "z_pov")]
M[, lab := c(busy = "Busyness\n(population, foot traffic,\ntransit, jobs)", z_d2 = "Distance to a restroom\nopen at 2pm",
             z_d9 = "Distance to a restroom\nopen at 9pm", z_pov = "Equity\n(tract poverty rate)")[term]]
M[, grp := c(busy = "Demand", z_d2 = "Supply", z_d9 = "Supply", z_pov = "Demand")[term]]
M[, lab := factor(lab, levels = rev(lab))]
p3 <- ggplot(M, aes(coef, lab, colour = grp)) + geom_vline(xintercept = 0, colour = "grey50") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.18, linewidth = 0.9, orientation = "y") + geom_point(size = 4) +
  scale_colour_manual(values = c(Demand = "#0b3d91", Supply = "#c0392b"), name = NULL) +
  labs(title = "The City chose busy places with no restroom open nearby, day or evening",
       subtitle = "Effect on the chance a site was chosen (standardised logistic coefficient, 95% interval)",
       x = "Pushes a site toward being chosen  →", y = NULL,
       caption = "Firth logistic regression: 17 pilot sites vs 5,756 candidate sites, controlling for site type (park / plaza / street).") +
  thb + theme(legend.position = "top")
save(p3, "g3_pilot_model.png", 9, 5.8)

# g4 -- leave-one-out
L <- fread(file.path(CM, "outputs/gap_leave_one_out.csv")); L[, name := factor(pilot, levels = pilot[order(loo_pct)])]
p4 <- ggplot(L, aes(loo_pct, name)) + geom_segment(aes(x = 0, xend = loo_pct, yend = name), colour = "grey75") +
  geom_point(size = 3.5, colour = "#0b3d91") + geom_vline(xintercept = median(L$loo_pct), linetype = 2, colour = "#c0392b") +
  annotate("text", x = median(L$loo_pct) - 1, y = 1.5, hjust = 1, label = sprintf("median %d%%", median(L$loo_pct)), colour = "#c0392b", size = 4.2) +
  scale_x_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "Hide one pilot site, refit, and it still ranks near the top",
       subtitle = "Share of 5,756 candidate sites each hidden pilot site outranks", x = NULL, y = NULL,
       caption = "Leave-one-out: the model is refitted 17 times, each time without one pilot site, which is then scored against all candidates.") + thb
save(p4, "g4_leave_one_out.png", 9, 6)

# g5 -- demand
cp$dem <- cut(G$D0, c(0, 1 / 3, 2 / 3, 1), labels = c("Lower third", "Middle third", "Top third"), include.lowest = TRUE)
p5 <- base() + geom_sf(data = cp[order(G$D0), ], aes(colour = dem), size = 0.55) +
  scale_colour_manual(values = c("Lower third" = "#d7dbe3", "Middle third" = "#8ea2c4", "Top third" = "#0b3d91"), name = "Demand at each candidate site") +
  guides(colour = guide_legend(override.aes = list(size = 4))) +
  labs(title = "Demand: where people are",
       subtitle = "Busyness (population, foot traffic, transit, jobs) 95% and equity 5%,\nweights learned from the City's 17 pilot sites",
       caption = "5,814 candidate sites: 150 m grid points on Parks land, DOT plazas and busy-street frontage.") + th
save(p5, "g5_demand.png")

# g6 -- supply by time of day
sup <- P$sup; op <- function(h) { cl <- ifelse(sup$placeholder, 16, sup$w_close); sup$operational & !sup$removed_closed & !sup$removed_fail & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
mkp <- function(cov, h, ttl) {
  cp$c <- factor(ifelse(cov, "Restroom open within 500 m", "None open within 500 m"), levels = c("Restroom open within 500 m", "None open within 500 m"))
  base() + geom_sf(data = cp, aes(colour = c), size = 0.45) + geom_sf(data = sup[op(h), ], shape = 16, size = 0.5, colour = "#111111") +
    scale_colour_manual(values = c("Restroom open within 500 m" = "#9fc5a8", "None open within 500 m" = "#c0392b"), name = NULL, drop = FALSE) +
    guides(colour = guide_legend(override.aes = list(size = 4))) +
    labs(title = ttl, subtitle = sprintf("%d working restrooms open · %d%% of sites covered", sum(op(h)), round(100 * mean(cov)))) + th +
    theme(plot.title = element_text(size = 15), legend.position = c(0.01, 0.9))
}
p6 <- (mkp(G$cov14, 14, "Supply at 2pm") | mkp(G$cov21, 21, "Supply at 9pm")) +
  plot_annotation(title = "Supply: by day most sites have a restroom nearby; by 9pm few do",
                  caption = "Listed restrooms by posted hours (register June 2025), excluding those Parks records as closed long-term or repeatedly failing inspection.\nParks restrooms posting only '8am-4pm, open later seasonally' assumed to close at 4pm.",
                  theme = theme(plot.title = element_text(face = "bold", size = 17), plot.caption = element_text(size = 9, colour = "grey40", hjust = 0),
                                plot.background = element_rect(fill = "white", colour = NA)))
save(p6, "g6_supply_day_evening.png", 14, 7.6)

# g7 -- the gap
cp$gt <- factor(ifelse(!G$gap0, NA, ifelse(G$cov14, "Evening-only gap: a restroom nearby by day, none by 9pm", "All-day gap: no restroom nearby at any time")),
                levels = c("Evening-only gap: a restroom nearby by day, none by 9pm", "All-day gap: no restroom nearby at any time"))
k <- table(cp$gt); levels(cp$gt) <- sprintf("%s (%d)", levels(cp$gt), as.integer(k))
p7 <- base() + geom_sf(data = cp[!G$gap0, ], colour = "#dcdcd8", size = 0.35) +
  geom_sf(data = cp[G$gap0, ], aes(colour = gt), size = 0.9) +
  geom_sf(data = pil, shape = 24, size = 2.6, fill = "white", colour = "#111111") +
  scale_colour_manual(values = setNames(c("#eda100", "#c0392b"), levels(cp$gt)), name = sprintf("Gap: top-third demand, nothing open at 9pm (%d sites)", sum(G$gap0))) +
  guides(colour = guide_legend(override.aes = list(size = 4))) +
  labs(title = "Demand minus supply: the gap is an evening gap",
       subtitle = sprintf("Triangles = the City's 17 pilot sites; %d of them fall inside this gap definition.", sum(G$pc_pil >= 2 / 3 & G$pil9)),
       caption = "Gap sites within 500 m of a pilot unit (open 7am-10pm) are treated as already served.") + th
save(p7, "g7_gap.png")

# g8 -- closing the gap: existing restrooms first, then new units
Fac <- G$Fac; New <- G$New
fp <- st_transform(st_as_sf(Fac, coords = c("lon", "lat"), crs = 4326), 2263); np <- pts(New)
A <- c("Keep park restroom open to 10pm", "Extend other operator's hours", "Repair or reopen")
fp$a <- factor(Fac$action, levels = A); k8 <- table(fp$a)
levels(fp$a) <- sprintf("%s (%d)", c("Keep a park restroom open to 10pm", "Extend another operator's hours to 10pm", "Repair, then keep open to 10pm"), as.integer(k8))
p8 <- base() + geom_sf(data = cp[G$gap0, ], colour = "#f1d9a8", size = 0.5) +
  geom_sf(data = fp, aes(fill = a), shape = 21, size = 2.8, colour = "white", stroke = 0.4) +
  geom_sf(data = np, aes(shape = sprintf("New modular unit (%d)", nrow(New))), size = 3.6, fill = "#c0392b", colour = "white", stroke = 0.6) +
  scale_fill_manual(values = setNames(c("#eda100", "#4a3aa7", "#2a78d6"), levels(fp$a)), name = sprintf("Stage 1: %d existing restrooms", nrow(Fac))) +
  scale_shape_manual(values = 23, name = "Stage 2") +
  guides(fill = guide_legend(order = 1, override.aes = list(size = 4)), shape = guide_legend(order = 2)) +
  labs(title = sprintf("Closing the gap: %d existing restrooms, then %d new units", nrow(Fac), nrow(New)),
       subtitle = sprintf("Existing restrooms placed first, at their own locations (they cover %d of %d gap sites);\nnew units only where no existing restroom can reach. Pale = gap sites.",
                          max(G$cum), sum(G$gap0)),
       caption = "Both stages: greedy maximal covering within 500 m, weighted by demand.\nBroken = Parks long-term closed, or failing >=50% of inspections since Jan 2025.") + th
save(p8, "g8_sites_and_actions.png")

# g8b -- diminishing returns of stage 1
cu <- data.table(k = seq_along(G$cum), share = G$cum / sum(G$gap0))
p8b <- ggplot(cu, aes(k, share)) + geom_line(linewidth = 1.1, colour = "#0b3d91") +
  geom_point(data = cu[k %in% c(25, 50, 100)], size = 3, colour = "#c0392b") +
  geom_text(data = cu[k %in% c(25, 50, 100)], aes(label = sprintf("%d restrooms: %d%%", k, round(100 * share))), hjust = -0.1, vjust = 1.4, size = 4) +
  scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), limits = c(0, 1)) +
  labs(title = "The first 50 existing restrooms close three-quarters of the gap",
       subtitle = "Share of the 9pm gap covered as existing restrooms are added, most useful first", x = "Existing restrooms repaired or kept open later", y = NULL) + thb
save(p8b, "g8b_diminishing_returns.png", 9, 5.2)

# g9 -- sensitivity: existing restrooms and new units by setting
SG <- copy(G$SG)
SG[, setting := sprintf("demand top %s · %dpm · %d m", c(`0.5` = "half", `0.67` = "third", `0.75` = "quarter")[as.character(threshold)], hour - 12, radius)]
SG[, parks := ifelse(park_close == 16, "Parks close 4pm (assumed)", "Parks open to 10pm")]
L9 <- melt(SG[, .(setting, parks, `Existing restrooms used` = existing, `New units` = new_units)], id.vars = c("setting", "parks"))
ordr <- SG[park_close == 16][order(new_units, existing)]$setting
L9[, setting := factor(setting, levels = unique(ordr))]
base_ex <- nrow(G$Fac); base_new <- nrow(G$New)
L9[, base := ifelse(variable == "New units", base_new, base_ex)]
p9 <- ggplot(L9, aes(value, setting, colour = parks)) + geom_point(size = 3) +
  geom_vline(aes(xintercept = base), linetype = 2, colour = "grey45") + facet_wrap(~variable, scales = "free_x") +
  scale_colour_manual(values = c("Parks close 4pm (assumed)" = "#0b3d91", "Parks open to 10pm" = "#eda100"), name = NULL) +
  labs(title = "Park hours change the existing restrooms needed, not the new units",
       subtitle = sprintf("Dashed = base case. Random demand weights (200 runs): existing %d-%d, new units %d-%d.",
                          min(G$RW$existing), max(G$RW$existing), min(G$RW$new_units), max(G$RW$new_units)),
       x = NULL, y = NULL) + thb + theme(legend.position = "top", strip.text = element_text(face = "bold", size = 12))
save(p9, "g9_sensitivity.png", 11, 7.5)

# g10 -- complaint hotspots
in29 <- nta[nta$nta2020 %in% D29$nta2020, ]
fp$in29 <- lengths(st_intersects(fp, in29)) > 0; np$in29 <- lengths(st_intersects(np, in29)) > 0; pil$in29 <- lengths(st_intersects(pil, in29)) > 0
p10 <- base() + geom_sf(data = in29, fill = "#f3d3cf", colour = "#c0392b", linewidth = 0.3) +
  geom_sf(data = pil, shape = 24, size = 2.6, fill = "white", colour = "#333333") +
  geom_sf(data = fp, shape = 21, size = 2.2, fill = "#0b3d91", colour = "white") +
  geom_sf(data = np, shape = 23, size = 3, fill = "#c0392b", colour = "white") +
  labs(title = "Complaint hotspots are a separate question",
       subtitle = sprintf("Pink = 29 neighbourhoods with 1.5x+ the complaints their crowds predict. Inside them:\n%d of 17 pilot sites (triangles), %d of %d existing restrooms (circles), %d of %d new units (diamonds).",
                          sum(pil$in29), sum(fp$in29), nrow(fp), sum(np$in29), nrow(np)),
       caption = "Complaint model: negative binomial regression of 311 public-urination complaints (2020-26) in 197 residential neighbourhoods.") + th
save(p10, "g10_complaints.png")
fwrite(data.table(pilots_in_29 = sum(pil$in29), existing_in_29 = sum(fp$in29), existing = nrow(fp), new_in_29 = sum(np$in29), new = nrow(np)),
       file.path(CM, "outputs/gap_overlap_with_29.csv"))

# complaints added to the pilot model (for the text)
Zd <- NULL
cat("figures written; pilots in 29:", sum(pil$in29), "| existing in 29:", sum(fp$in29), "| new in 29:", sum(np$in29), "\n")
