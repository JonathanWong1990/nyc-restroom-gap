# 04_figures.R -- slide figures for the City Criteria Model tab. Reads outputs of 01-03 (quota run). Writes outputs/fig/*.png
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table); library(ggplot2)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FIG <- file.path(CM, "outputs/fig"); dir.create(FIG, showWarnings = FALSE)
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds"))
X <- readRDS(file.path(CM, "cache/features.rds"))$X
S <- fread(file.path(CM, "outputs/next50_sites_revealed_borough_quota.csv"))
R <- fread(file.path(CM, "outputs/robustness_models.csv")); LOO <- fread(file.path(CM, "outputs/leave_one_out_M4.csv"))
D29 <- fread(file.path(BASE, "Build_Plan/layered/outputs/diagnosis_29_final.csv"))
nta <- st_simplify(P$nta, dTolerance = 40, preserveTopology = TRUE)
th <- theme_void(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 17), plot.subtitle = element_text(size = 12, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), legend.position = c(0.01, 0.99),
        legend.justification = c(0, 1), legend.text = element_text(size = 11), legend.title = element_text(size = 11.5, face = "bold"),
        legend.background = element_rect(fill = alpha("white", 0.85), colour = NA),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 10, 10, 10))
thb <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold", size = 16), plot.subtitle = element_text(size = 12, colour = "grey30"),
        plot.caption = element_text(size = 9, colour = "grey40", hjust = 0), panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "white", colour = NA))
base <- function() ggplot() + geom_sf(data = nta, fill = "#ecebe8", colour = "white", linewidth = 0.15)
pts <- function(d) st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), 2263)
pil <- pts(X[pilot == 1]); s50 <- pts(S)
save <- function(p, f, w = 8.5, h = 9) ggsave(file.path(FIG, f), p, width = w, height = h, dpi = 150)

# f1 -- restrooms open by time of day
sup <- P$sup; op <- function(h) { cl <- ifelse(sup$placeholder, 16, sup$w_close); sum(sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h) }
hrs <- 6:23; oa <- data.table(h = hrs, n = sapply(hrs, op))
stopifnot(op(14) == 954, op(21) == 57)
p1 <- ggplot(oa, aes(h, n)) + geom_col(fill = "#8a9bb0", width = 0.8) +
  geom_col(data = oa[h %in% c(14, 21)], fill = "#c0392b", width = 0.8) +
  annotate("text", x = 14, y = 954 + 45, label = "954 at 2pm", fontface = "bold", size = 4.5) +
  annotate("text", x = 21, y = 57 + 45, label = "57 at 9pm", fontface = "bold", size = 4.5, colour = "#c0392b") +
  scale_x_continuous(breaks = seq(6, 23, 2), labels = function(x) sprintf("%d:00", x)) +
  labs(title = "Of 975 listed public restrooms, only 57 are open at 9pm",
       subtitle = "Restrooms open at each hour of a weekday, by posted hours", x = NULL, y = "Restrooms open",
       caption = "NYC public restroom register (June 2025). Parks restrooms posting only '8am-4pm, open later seasonally' are assumed to close at 4pm.") + thb
save(p1, "f1_open_by_hour.png", 9, 5.2)

# f2 -- the 17 pilot sites
pil$type_l <- factor(c(park = "Park or playground", plaza = "Public plaza", busy_street = "Street corner")[pil$type],
                     levels = c("Public plaza", "Park or playground", "Street corner"))
p2 <- base() + geom_sf(data = pil, aes(fill = type_l), shape = 21, size = 4.2, colour = "white", stroke = 0.8) +
  scale_fill_manual(values = c("Public plaza" = "#c0392b", "Park or playground" = "#2a78d6", "Street corner" = "#eda100"), name = "The City's 17 pilot sites") +
  labs(title = "The City's first move: 17 modular toilets, September 2026",
       subtitle = "4 per borough (1 on Staten Island), mostly plazas and parks, open 7am-10pm",
       caption = "Locations: Mayor's Office release, 16 Sep 2026; geocoded. Site type from Parks properties and DOT plazas within 30 m.") + th
save(p2, "f2_pilot_sites.png")

# f3 -- what the City's choices reveal (preferred model M4, plus complaints from M6)
m4 <- R[model == "M4 busyness index + site type" & term %in% c("busy", "z_dist", "z_pov")]
m6 <- R[model == "M6 as M4 + complaints" & term == "z_311"]
cf <- rbind(m4, m6)
cf[, lab := c(busy = "Busyness\n(population, foot traffic,\ntransit, jobs)", z_dist = "Distance to the nearest\nrestroom open at 2pm",
              z_pov = "Equity\n(tract poverty rate)", z_311 = "Public-urination\ncomplaints (not in the law)")[term]]
cf[, lab := factor(lab, levels = rev(lab))]
w <- pmax(m4$coef, 0); w <- round(100 * w / sum(w))
cf[, wlab := c(sprintf("%d%% of the weight", w), "not a factor")]
cf[, col := c("in", "in", "in", "out")]
p3 <- ggplot(cf, aes(coef, lab)) + geom_vline(xintercept = 0, colour = "grey50") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high, colour = col), width = 0.18, linewidth = 0.9, orientation = "y") +
  geom_point(aes(colour = col), size = 4) + geom_text(aes(label = wlab), nudge_y = 0.32, size = 4) +
  scale_colour_manual(values = c("in" = "#0b3d91", "out" = "grey55"), guide = "none") +
  labs(title = "What the City's 17 choices reveal: busy places far from a restroom",
       subtitle = "Effect on the chance a site was chosen (standardised logistic coefficient, 95% interval)",
       x = "Pushes a site toward being chosen  →", y = NULL,
       caption = "Firth logistic regression: 17 pilot sites vs 5,756 candidate sites (Parks land, DOT plazas, busy streets), controlling for site type.\nFactors from Local Law 58's definition of an underserved area. Complaints tested separately; not significant.") + thb
save(p3, "f3_revealed_weights.png", 9, 5.6)

# f4 -- leave-one-out
LOO[, name := factor(pilot, levels = pilot[order(loo_pct_M4)])]
p4 <- ggplot(LOO, aes(loo_pct_M4, name)) + geom_segment(aes(x = 0, xend = loo_pct_M4, yend = name), colour = "grey75") +
  geom_point(size = 3.5, colour = "#0b3d91") + geom_vline(xintercept = median(LOO$loo_pct_M4), linetype = 2, colour = "#c0392b") +
  annotate("text", x = median(LOO$loo_pct_M4) - 1, y = 1.5, hjust = 1, label = sprintf("median %d%%", median(LOO$loo_pct_M4)), colour = "#c0392b", size = 4.2) +
  scale_x_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "Hide one pilot site, refit, and it still ranks near the top",
       subtitle = "Share of 5,756 candidate sites each hidden pilot site outranks", x = NULL, y = NULL,
       caption = "Leave-one-out: the model is refitted 17 times, each time without one pilot site, which is then scored against all candidates.") + thb
save(p4, "f4_leave_one_out.png", 9, 6)

# f5 -- next 50 and their stability
s50$stab <- factor(ifelse(s50$stable_revealed >= .8 & s50$stable_any >= .5, "Robust: chosen under almost any weighting",
                   ifelse(s50$stable_revealed >= .8, "Holds within the model's uncertainty", "Depends on the weights")),
                   levels = c("Robust: chosen under almost any weighting", "Holds within the model's uncertainty", "Depends on the weights"))
k <- table(s50$stab); levels(s50$stab) <- sprintf("%s (%d)", levels(s50$stab), as.integer(k))
p5 <- base() + geom_sf(data = pil, shape = 24, size = 2.4, fill = "white", colour = "#333333") +
  geom_sf(data = s50, aes(fill = stab), shape = 21, size = 4, colour = "white", stroke = 0.6) +
  scale_fill_manual(values = setNames(c("#0b3d91", "#6f9bd1", "#d0d7e2"), levels(s50$stab)), name = "The next 50 sites") +
  labs(title = "The next 50 sites, and how many survive any weighting",
       subtitle = "Split by borough population: Bronx 8, Brooklyn 15, Manhattan 10, Queens 14, Staten Island 3.\nTriangles = the City's 17 pilot sites.",
       caption = "Robust: picked in >=80% of 2,000 runs within the model's uncertainty AND >=50% of 2,000 runs with random weights.\nSites at least 500 m apart and from pilot sites.") + th
save(p5, "f5_next50_stability.png")

# f6 -- reality lens
LENS <- c("Build: no restroom within 500 m" = "Build a new unit",
          "Extend park hours nearby first" = "Keep a nearby park restroom open later",
          "Repair or reopen nearby first" = "Repair or reopen a nearby restroom",
          "Existing restroom closes early: extend other operator's hours" = "Nearby library/other restroom closes early",
          "Covered day and evening: lower priority" = "Already covered day and evening")
s50$lens <- factor(LENS[s50$reality_lens], levels = LENS); k6 <- table(s50$lens)
levels(s50$lens) <- sprintf("%s (%d)", levels(s50$lens), as.integer(k6))
p6 <- base() + geom_sf(data = s50, aes(fill = lens), shape = 21, size = 4.2, colour = "white", stroke = 0.6) +
  scale_fill_manual(values = setNames(c("#c0392b", "#eda100", "#2a78d6", "#4a3aa7", "#b5b5b5"), levels(s50$lens)), drop = FALSE, name = "What each site needs first") +
  labs(title = sprintf("Reality lens: only %d of the 50 need a new building", as.integer(k6[1])),
       subtitle = "Checks each site against restrooms within 500 m: open at 2pm? at 9pm? closed or failing inspection?",
       caption = "Posted hours (park placeholder hours = 4pm). Broken = Parks long-term closed or failing >=50% of inspections since Jan 2025.") + th
save(p6, "f6_reality_lens.png")

# f7 -- our complaint hotspots vs the City's and our picks
in29 <- nta[nta$nta2020 %in% D29$nta2020, ]
s50$in29 <- lengths(st_intersects(s50, in29)) > 0; pil$in29 <- lengths(st_intersects(pil, in29)) > 0
cat("pilots in the 29:", sum(pil$in29), "| next-50 in the 29:", sum(s50$in29), "\n")
p7 <- base() + geom_sf(data = in29, fill = "#f3d3cf", colour = "#c0392b", linewidth = 0.3) +
  geom_sf(data = pil, shape = 24, size = 3, fill = "white", colour = "#333333") +
  geom_sf(data = s50, shape = 21, size = 3.2, fill = "#0b3d91", colour = "white") +
  labs(title = "The City's factors do not point to where complaints run high",
       subtitle = sprintf("Pink = 29 neighbourhoods with 1.5x+ the complaints their crowds predict.\n%d of the 17 pilot sites (triangles) and %d of our next 50 (dots) fall inside them.", sum(pil$in29), sum(s50$in29)),
       caption = "Complaint model: negative binomial regression of 311 public-urination complaints on crowd measures (earlier analysis, archived).") + th
save(p7, "f7_complaint_hotspots.png")
fwrite(data.table(pilots_in_29 = sum(pil$in29), next50_in_29 = sum(s50$in29)), file.path(CM, "outputs/overlap_with_29.csv"))
cat("figures written\n")
