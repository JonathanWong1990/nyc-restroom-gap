# A7_repair_vs_build.R — what does FIXING a restroom cost against BUILDING one?
#
# The project's headline cost ($2,331,000, from A2_cost_bands.R) pools every restroom
# capital project. But the decision Local Law 58 forces is narrower: LL58 plans NEW
# capacity, while the PIP condition series (A8) says the EXISTING stock is failing.
# Those are different budget lines with very different prices, so separate them.
#
# Classification is on the restroom-specific phrase, because a title like "Arcilla
# Playground Reconstruction and Public Restroom Building Construction" is a NEW
# restroom beside a rebuilt playground.
suppressMessages(library(dplyr)); options(scipen=999)
D <- Sys.getenv("RESTROOM_PROJ", unset="."); dd <- file.path(D,"data_raw")
ct <- read.csv(file.path(dd,"capitaltracker_4hcv-tc5r_20260920.csv")) |>
  distinct(trackerid, .keep_all=TRUE) |>
  filter(grepl("restroom|comfort station|bathroom", paste(title,summary), ignore.case=TRUE))
tx <- tolower(paste(ct$title, ct$summary))

## ---- value the banded rows (same logic as A2) ------------------------------
num   <- suppressWarnings(as.numeric(gsub("[^0-9.]","",ct$totalfunding)))
isnum <- grepl("^[[:space:]]*\\$?[0-9,.]+[[:space:]]*$", ct$totalfunding)
band <- function(s){ s <- tolower(s)
  ifelse(grepl("less than \\$?1 ?m", s), 0.5e6,
  ifelse(grepl("between \\$?1 ?m.*\\$?3 ?m|1 million and \\$?3", s), 2e6,
  ifelse(grepl("between \\$?3 ?m.*\\$?5 ?m|3 million and \\$?5", s), 4e6,
  ifelse(grepl("between \\$?5 ?m.*\\$?10 ?m|5 million and \\$?10", s), 7.5e6,
  ifelse(grepl("greater than \\$?10", s), 12.5e6, NA))))) }
ct$cost <- ifelse(isnum, num, band(ct$totalfunding))

## ---- classify --------------------------------------------------------------
RM   <- "restroom|comfort station|bathroom"
recon <- grepl(paste0("(",RM,")[a-z ]*reconstruction"), tx)
newb  <- grepl(paste0("(",RM,")[a-z ]*construction"), tx) & !recon
comp  <- grepl("plumbing system|roof|electrical system|hvac|boiler|heating system", tx) & !recon & !newb
ct$type <- ifelse(recon,"Reconstruct existing",
           ifelse(newb,"Build new",
           ifelse(comp,"Component work (roof/plumbing/electrical)","Other / unclear")))

cat("=== restroom capital projects by type ===\n")
print(ct |> group_by(type) |> summarise(n=n(), with_cost=sum(!is.na(cost)),
        median=median(cost,na.rm=TRUE), q1=quantile(cost,.25,na.rm=TRUE),
        q3=quantile(cost,.75,na.rm=TRUE)) |> arrange(desc(n)) |> as.data.frame())

nb <- median(ct$cost[ct$type=="Build new"], na.rm=TRUE)
rc <- median(ct$cost[ct$type=="Reconstruct existing"], na.rm=TRUE)
cp <- median(ct$cost[ct$type=="Component work (roof/plumbing/electrical)"], na.rm=TRUE)
cat(sprintf("\nBuild new            median $%s  (n=%d)\n", format(round(nb),big.mark=","), sum(ct$type=="Build new" & !is.na(ct$cost))))
cat(sprintf("Reconstruct existing median $%s  (n=%d)\n", format(round(rc),big.mark=","), sum(ct$type=="Reconstruct existing" & !is.na(ct$cost))))
cat(sprintf("Component work       median $%s  (n=%d)\n", format(round(cp),big.mark=","), sum(grepl("^Component", ct$type) & !is.na(ct$cost))))
cat(sprintf("\n=> one new build buys %.0f component jobs, or %.1f reconstructions\n", nb/cp, nb/rc))

## ---- how many facilities are actually out of service? ----------------------
cat("\n=== facilities currently out of service ===\n")
f <- file.path(dd,"pipRestrooms_9byw-znpj_20260920.csv")
if (file.exists(f)) {
  pr <- read.csv(f)
  cl <- grep("closure|closed|status", names(pr), ignore.case=TRUE, value=TRUE)
  cat("rows:", nrow(pr), "  status-ish cols:", paste(cl, collapse=" | "), "\n")
  for (c in cl) { tb <- sort(table(pr[[c]][nzchar(trimws(pr[[c]]))]), decreasing=TRUE)
                  if (length(tb) && length(tb) < 15) { cat("\n", c, ":\n"); print(tb) } }
} else cat("pipRestrooms_9byw-znpj not in data_raw — pull it before citing closure counts\n")

rs <- read.csv(file.path(dd,"nycrestrooms_i7jb-7jku_20260920.csv"))
cat("\nnycrestrooms status field:\n"); print(sort(table(rs$status), decreasing=TRUE))
