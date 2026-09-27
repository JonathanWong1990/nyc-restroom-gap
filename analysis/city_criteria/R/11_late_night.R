# 11_late_night.R -- after 10pm: subway entries by hour, public-urination complaints by filing hour, working restrooms open.
# Inputs: MTA average entries by day type and hour, 2025 (team research package, Steph); 311 "Urinating in Public" 2020-26;
# restroom register with the same supply rule as 05_gap.R (broken restrooms excluded). Writes outputs/late_night.csv.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressMessages(library(data.table))
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
m <- fread(file.path(BASE, "Team_Inbox/FILED_03_Restroom_Package/NYC Restroom Problem - Package/data/demand/mta_subway_average_entries_by_daytype_hour_2025.csv"))
u <- fread(file.path(BASE, "Restroom_Rebuild/data_raw/nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))[complaint_type == "Urinating in Public"]
h <- as.integer(substr(u$created_date, 12, 13))
s <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds"))$sup
op <- function(hh) { cl <- ifelse(s$placeholder, 16, s$w_close); sum(s$operational & !s$removed_closed & !s$removed_fail & s$w_ok & !is.na(s$w_open) & s$w_open <= hh & cl > hh) }
sh <- function(d, hrs) { w <- m[day_type == d]; round(100 * sum(w[hour %in% hrs]$average_entries) / sum(w$average_entries), 1) }
R <- data.table(
  measure = c("weekday subway entries, share 6-10pm", "weekday subway entries, share 10pm-midnight", "weekday subway entries, share midnight-6am",
              "weekday subway entries 10pm-6am (count)", "Saturday subway entries, share 10pm-6am", "Saturday subway entries 10pm-6am (count)",
              "complaints filed 6-10pm (%)", "complaints filed 10pm-midnight (%)", "complaints filed midnight-6am (%)", "complaints (n)",
              "working restrooms open 9pm", "10pm", "11pm", "midnight", "2am"),
  value = c(sh("Weekday", 18:21), sh("Weekday", 22:23), sh("Weekday", 0:5),
            round(sum(m[day_type == "Weekday" & (hour >= 22 | hour < 6)]$average_entries)), sh("Saturday", c(22:23, 0:5)),
            round(sum(m[day_type == "Saturday" & (hour >= 22 | hour < 6)]$average_entries)),
            round(100 * mean(h >= 18 & h < 22), 1), round(100 * mean(h >= 22), 1), round(100 * mean(h < 6), 1), length(h),
            op(21), op(22), op(23), op(24), op(2)))
print(R); fwrite(R, file.path(CM, "outputs/late_night.csv"))
