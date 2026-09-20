# A2_cost_bands.R — the excluded "banded" projects are the expensive ones. Value them.
suppressMessages(library(dplyr)); options(scipen=999)
ct <- read.csv("data_raw/capitaltracker_4hcv-tc5r_20260920.csv") |>
  distinct(trackerid, .keep_all=TRUE) |>
  filter(grepl("restroom|comfort station|bathroom", paste(title,summary), ignore.case=TRUE))
num <- suppressWarnings(as.numeric(gsub("[^0-9.]","",ct$totalfunding)))
isnum <- grepl("^[[:space:]]*\\$?[0-9,.]+[[:space:]]*$", ct$totalfunding)
cat("restroom projects:", nrow(ct), " numeric:", sum(isnum), " banded/text:", sum(!isnum), "\n\n")
cat("the excluded rows:\n"); print(sort(table(ct$totalfunding[!isnum]), decreasing=TRUE))

band <- function(s, where){
  s <- tolower(s)
  lo <- function(a,b) if(where=="lo") a else if(where=="hi") b else (a+b)/2
  ifelse(grepl("less than \\$?1 ?m", s), lo(0, 1e6),
  ifelse(grepl("between \\$?1 ?m.*\\$?3 ?m|1 million and \\$?3", s), lo(1e6,3e6),
  ifelse(grepl("between \\$?3 ?m.*\\$?5 ?m|3 million and \\$?5", s), lo(3e6,5e6),
  ifelse(grepl("between \\$?5 ?m.*\\$?10 ?m|5 million and \\$?10", s), lo(5e6,10e6),
  ifelse(grepl("greater than \\$?10", s), lo(10e6,15e6), NA)))))
}
for(w in c("lo","mid","hi")){
  v <- ifelse(isnum, num, band(ct$totalfunding, w))
  cat(sprintf("\nband values at %-3s bound -> n=%d  MEDIAN $%s  (numeric-only median $%s)\n",
      w, sum(!is.na(v)), format(round(median(v,na.rm=TRUE)),big.mark=","),
      format(round(median(num[isnum])),big.mark=",")))
}
v <- ifelse(isnum, num, band(ct$totalfunding,"mid"))
cat(sprintf("\n=> published $1,559,000 is the median of the CHEAP HALF.\n"))
cat(sprintf("   %.0f%% of excluded projects are >= $3M, vs %.0f%% of included ones.\n",
    100*mean(grepl("3 million|5 million|Greater than", ct$totalfunding[!isnum])),
    100*mean(num[isnum] >= 3e6)))
cat(sprintf("   corrected median: $%s  -> annualised (20yr, 3.5%%) $%s/yr\n",
    format(round(median(v,na.rm=TRUE)),big.mark=","),
    format(round(median(v,na.rm=TRUE)*(.035*1.035^20)/(1.035^20-1)),big.mark=",")))
cat(sprintf("   Local Law 58 gap: 1,147 x corrected median = $%.2f billion\n",
    1147*median(v,na.rm=TRUE)/1e9))
