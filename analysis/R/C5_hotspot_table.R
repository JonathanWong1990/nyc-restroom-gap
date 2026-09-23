# C5_hotspot_table.R -----------------------------------------------------------
# Site-ready hot-spot table: ONE ROW PER HIGH-CONFIDENCE NTA, built only from
# C3's saved output (outputs/station_bridge.json, test4_hotspots: DBSCAN eps 150 m,
# minPts 5, Brighton Beach fallback minPts 4; Wednesday; open-at-9pm is
# season-invariant). Nothing is recomputed; no data is pulled.
#
# Row = the NTA's LARGEST hot spot (ties: nearest to a station), plus an NTA-level
# anchoring verdict over ALL its hot spots and a one-line list of the others.
#   Anchoring (C3 rule: hot-spot centroid within 250 m of a station complex)
#     station-anchored : every hot spot anchored
#     mixed            : some anchored, some not
#     not anchored     : none anchored (or no station at all)
#   Natural owner (of the PRIMARY hot spot; a judgement rule, stated so it can be argued):
#     anchored (<= 250 m of a station)             -> "MTA / DOT (station exit, sidewalk)"
#     else centroid <= 60 m of a Parks property   -> "Parks (adjacent park/playground)"
#     else                                         -> "DOT (street) / private frontage"
#   Thin flags: NTA < 30 complaints (C3 Test 1 rule); hot spot < 10 complaints;
#   hot spot with < 5 distinct addresses (a few repeat reporters can make it).
# Plain-words locations are hand-written from C3's top addresses and map review
# (station_bridge_findings.md, Test 4) and CHECKED against the top-address strings
# below, so a rerun of C3 that moves a cluster will fail here rather than mislabel.
# -----------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(dplyr); library(jsonlite)})
PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
OUT <- file.path(PROJ, "outputs"); WALK <- 72

h <- fromJSON(file.path(OUT, "station_bridge.json"))$test4_hotspots
stopifnot(nrow(h) == 18)
# plain words: key = ntaname|cluster ; check = a substring that must appear in top_addresses
pw <- read.csv(text = "key|plain|check
East Harlem (North)|1|Park Ave at E 124-125 St, under the Metro-North viaduct|PARK AVENUE
East Harlem (North)|2|E 116-117 St at Lexington Ave|116 STREET
East Harlem (North)|3|E 122 St between 2nd and 3rd Ave|122 STREET
East Harlem (North)|4|E 124-126 St between Lexington and 3rd Ave|124 STREET
East Harlem (North)|5|E 128 St at Madison Ave|128 STREET
Astoria (East)-Woodside (North)|1|28 Ave at 56 Pl, Woodside (North)|56 PLACE
Astoria (East)-Woodside (North)|2|Broadway at 41-42 St (Steinway St commercial strip)|BROADWAY
East Elmhurst|1|25 Ave at 85 St, at Gorman Playground|GORMAN
Williamsbridge-Olinville|1|E 211 St by the Gun Hill Rd (2,5) station|211 STREET
Williamsbridge-Olinville|2|Cruger Ave at Magenta St, by Gun Hill Playground|CRUGER
Brighton Beach|1|Brighton 8 St at Coney Island Ave|CONEY ISLAND
Brighton Beach|2|Ocean Pkwy malls at the Ocean Pkwy (Q) station|OCEAN PARKWAY
Brighton Beach|3|Brighton 4-5 St at Oceanview Ave|BRIGHTON 5
Midtown-Times Square|1|Columbus Circle / 8 Ave at 58 St|8 AVENUE
Midtown-Times Square|2|Broadway at 39-40 St (Garment District)|BROADWAY
Midtown-Times Square|3|Central Park South at 57 St / 7 Ave|CENTRAL PARK SOUTH
Midtown-Times Square|4|7 Ave at 51-53 St|7 AVENUE
Midtown-Times Square|5|Times Square at 42-43 St|TIMES SQUARE", sep = "|", header = FALSE, skip = 1,
  col.names = c("ntaname", "cluster", "plain", "check"))
h <- h |> left_join(pw, by = c("ntaname", "cluster"))
ok <- mapply(function(a, b) grepl(b, a, fixed = TRUE), toupper(h$top_addresses), h$check)
if (!all(ok)) { print(h[!ok, c("ntaname", "cluster", "top_addresses", "check")]); stop("plain-words labels no longer match C3 clusters") }

h$owner <- ifelse(h$d_station_m <= 250, "MTA / DOT (station exit, sidewalk)",
             ifelse(h$d_park_m <= 60, "Parks (adjacent park/playground)", "DOT (street) / private frontage"))
tot <- fromJSON(file.path(OUT, "station_bridge.json"))$test1
SIXO <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
          "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")
rows <- lapply(SIXO, function(nm) {
  x <- h[h$ntaname == nm, ]; x <- x[order(-x$n, x$d_station_m), ]; p <- x[1, ]
  anch <- if (all(x$station_anchored)) "station-anchored" else if (any(x$station_anchored)) "mixed" else "not anchored"
  nta_n <- tot$complaints[tot$ntaname == nm]
  others <- if (nrow(x) > 1) paste(sprintf("%s (%d; %s)", x$plain[-1], x$n[-1],
                                           ifelse(x$station_anchored[-1], "anchored", "not anchored")), collapse = "; ") else ""
  flags <- c(if (nta_n < 30) sprintf("thin area (%d complaints)", nta_n),
             if (p$n < 10) sprintf("thin hot spot (%d)", p$n),
             if (p$distinct_addr < 5) sprintf("%d distinct addresses", p$distinct_addr),
             if (grepl("fallback", p$params)) "clusters found only at minPts 4",
             if (p$years != "2020-2026" && !grepl("202[56]$", p$years)) sprintf("complaints %s only", p$years))
  data.frame(ntaname = nm, nta_complaints = nta_n, n_hotspots = nrow(x),
    hotspot_complaints_share = round(sum(x$n) / nta_n, 2),
    anchoring = anch, anchored_hotspots = sprintf("%d of %d", sum(x$station_anchored), nrow(x)),
    primary_hotspot = p$plain, primary_n = p$n, primary_distinct_addresses = p$distinct_addr,
    primary_share_evening_night = round(p$share_evening_night, 2), primary_years = p$years,
    lat = round(p$lat, 5), lon = round(p$lon, 5),
    nearest_station = p$nearest_station, station_m = p$d_station_m, station_anchored = p$station_anchored,
    nearest_listed_restroom = p$nearest_restroom, listed_m = p$d_restroom_m,
    nearest_open_9pm = p$nearest_open9pm, open_9pm_m = p$d_open9pm_m, open_9pm_walk_min = round(p$d_open9pm_m / WALK, 1),
    nearest_park = p$nearest_park, park_m = p$d_park_m, natural_owner = p$owner,
    thin_flags = paste(flags, collapse = "; "), other_hotspots = others)
})
tab <- bind_rows(rows)
write.csv(tab, file.path(OUT, "hotspot_table.csv"), row.names = FALSE)
write.csv(h |> select(ntaname, cluster, plain, n, distinct_addr, station_anchored, nearest_station, d_station_m,
                      nearest_restroom, d_restroom_m, nearest_open9pm, d_open9pm_m, nearest_park, d_park_m, owner,
                      share_evening_night, years, lat, lon),
          file.path(OUT, "hotspot_table_all_clusters.csv"), row.names = FALSE)
options(width = 220)
print(tab |> select(ntaname, nta_complaints, anchoring, anchored_hotspots, primary_hotspot, primary_n, primary_distinct_addresses,
                    nearest_station, station_m, nearest_listed_restroom, listed_m, nearest_open_9pm, open_9pm_m, natural_owner, thin_flags), row.names = FALSE)
cat("Wrote outputs/hotspot_table.csv (+ hotspot_table_all_clusters.csv)\n")
