# parse_hours.R ---------------------------------------------------------------
# Converts the free-text `hours_of_operation` field of NYC Public Restrooms
# (Socrata i7jb-7jku) into a tidy facility_id x day_of_week x open_hour x close_hour
# table, with an explicit unparseable flag.
#
# Output columns:
#   facility_id   integer row key into the restroom inventory
#   facility_name
#   day_of_week   1=Sunday .. 7=Saturday
#   open_hour     numeric decimal hour, 0-24 (e.g. 9.5 = 9:30am)
#   close_hour    numeric decimal hour; may EXCEED 24 for past-midnight closes
#                 (e.g. 6am-1am -> open 6, close 25). Always > open_hour.
#   is_open       FALSE for days explicitly marked Closed
#   parsed        TRUE if hours were recovered for this facility
#   parse_method  which format family matched
#   dusk_assumed  TRUE if "dusk"/"sunset" was substituted with DUSK_HOUR
#   multi_range   TRUE if the text held >1 range for the day (we keep the FIRST,
#                 which is the seasonal/summer schedule in this dataset)
#
# Honest limitations are recorded in notes/supply.md. `dusk` is NOT a clock time;
# we substitute a constant and flag it so downstream analysis can drop those rows.
# -----------------------------------------------------------------------------

options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(dplyr); library(tidyr)})

DUSK_HOUR <- 20.0   # NYC annual-average civil dusk, used only when flagged

DAYS <- c("sunday","monday","tuesday","wednesday","thursday","friday","saturday")

# --- normalise ---------------------------------------------------------------
norm_hours <- function(x) {
  x <- as.character(x)
  x <- gsub("–|—|−|‐|‑", "-", x)   # unicode dashes
  x <- gsub(" ", " ", x)                              # nbsp
  x <- tolower(x)
  x <- gsub("([ap])\\.\\s*m\\.", "\\1m", x)          # "7 a.m." -> "7 am"
  x <- gsub("noon", "12:00pm", x, fixed = TRUE)
  x <- gsub("midnight", "12:00am", x, fixed = TRUE)
  x <- gsub("sunset|sundown|dusk", "DUSKTOK", x)
  x <- gsub("[ \t]+", " ", x)
  trimws(x)
}

# --- parse a single clock time to a decimal hour -----------------------------
to_hour <- function(tok) {
  tok <- trimws(tok)
  if (grepl("DUSKTOK", tok, ignore.case = TRUE)) return(DUSK_HOUR)
  m <- regmatches(tok, regexec("^([0-9]{1,2})(?::([0-9]{2}))?\\s*(am|pm)?$", tok))[[1]]
  if (length(m) == 0) return(NA_real_)
  h <- as.numeric(m[2]); mi <- ifelse(m[3] == "", 0, as.numeric(m[3])); ap <- m[4]
  if (is.na(h) || h > 24) return(NA_real_)
  if (ap == "pm" && h < 12) h <- h + 12
  if (ap == "am" && h == 12) h <- 0
  h + mi / 60
}

TIME_RE  <- "([0-9]{1,2}(?::[0-9]{2})?\\s*(?:am|pm)?|DUSKTOK)"
RANGE_RE <- paste0(TIME_RE, "\\s*(?:-|to|until|till)\\s*", TIME_RE)

# extract every open/close pair from a fragment
extract_ranges <- function(s) {
  m <- gregexpr(RANGE_RE, s, perl = TRUE)
  hits <- regmatches(s, m)[[1]]
  if (length(hits) == 0) return(NULL)
  res <- lapply(hits, function(h) {
    p <- regmatches(h, regexec(RANGE_RE, h, perl = TRUE))[[1]]
    o <- to_hour(p[2]); c_ <- to_hour(p[3])
    if (is.na(o) || is.na(c_)) return(NULL)
    # meridiem inheritance: "4:00-10:00pm" means 4 PM, not 4 AM. If the OPEN
    # token carries no am/pm but the CLOSE says pm, promote the open to pm
    # whenever that still yields a sane same-day interval.
    o_bare <- !grepl("am|pm", p[2]) && !grepl("DUSKTOK", p[2], ignore.case = TRUE)
    if (o_bare && grepl("pm", p[3]) && o < 12 && (o + 12) < c_) o <- o + 12
    # an unsuffixed open before a pm close is almost always am-side; and a close
    # earlier than the open means it rolls past midnight (6am-1am -> 25)
    if (c_ <= o) c_ <- c_ + 24
    if (c_ - o > 24) return(NULL)
    data.frame(open_hour = o, close_hour = c_,
               dusk = grepl("DUSKTOK", h, ignore.case = TRUE))
  })
  res <- do.call(rbind, Filter(Negate(is.null), res))
  if (is.null(res) || nrow(res) == 0) NULL else res
}

# --- day-token expansion -----------------------------------------------------
DAY_ALIAS <- c(sun="sunday", su="sunday", sunday="sunday",
               mon="monday", m="monday", monday="monday",
               tue="tuesday", tues="tuesday", tu="tuesday", tuesday="tuesday",
               wed="wednesday", weds="wednesday", w="wednesday", wednesday="wednesday",
               thu="thursday", thur="thursday", thurs="thursday", th="thursday", thursday="thursday",
               fri="friday", f="friday", friday="friday",
               sat="saturday", sa="saturday", saturday="saturday")

day_idx <- function(d) match(d, DAYS)

expand_day_range <- function(a, b) {
  ia <- day_idx(a); ib <- day_idx(b)
  if (is.na(ia) || is.na(ib)) return(character(0))
  idx <- if (ia <= ib) ia:ib else c(ia:7, 1:ib)
  DAYS[idx]
}

# Long-form tokens only. Single-letter codes (m, f, w, su, sa) are NOT here:
# they produce false positives ("a.m." -> monday). They are handled solely by
# the explicit short-range pattern SHORTRANGE_RE below.
DAYTOK <- "\\b(sundays?|mondays?|tuesdays?|tues|wednesdays?|weds|thursdays?|thurs|thur|fridays?|saturdays?|sun|mon|tue|wed|thu|fri|sat|weekdays?|weekends?|daily|everyday|every day)\\b"
# "M-F", "S-S", "M-Su", "Tu-Sa" style
SHORTRANGE_RE <- "\\b(su|sa|m|tu|w|th|f|s)\\s*-\\s*(su|sa|m|tu|w|th|f|s)\\b"
DAYCONNECT <- "\\s*(?:-|to|thru|through|&|and)\\s*"

resolve_daytok <- function(tok) {
  tok <- gsub("s$", "", trimws(tok))
  if (tok %in% c("weekday")) return(DAYS[2:6])
  if (tok %in% c("weekend")) return(DAYS[c(1,7)])
  if (tok %in% c("daily","everyday","every day")) return(DAYS)
  v <- DAY_ALIAS[tok]
  if (is.na(v)) character(0) else unname(v)
}

# a leading day spec like "mon-fri", "m-f", "sat-sun", "weekdays", "s-s"
parse_day_spec <- function(spec) {
  spec <- trimws(gsub("[:,]", " ", spec))
  # "s-s" is used in this dataset for Sat-Sun (weekend), not Sunday-Sunday
  if (grepl("^s\\s*-\\s*s$", spec)) return(DAYS[c(1,7)])
  sr <- regmatches(spec, regexec(paste0("^", SHORTRANGE_RE, "$"), spec))[[1]]
  if (length(sr) == 3) {
    a <- resolve_daytok(sr[2]); b <- resolve_daytok(sr[3])
    if (length(a) == 1 && length(b) == 1) return(expand_day_range(a, b))
  }
  rng <- regmatches(spec, regexec(paste0("^", DAYTOK, DAYCONNECT, DAYTOK, "$"), spec, perl = TRUE))[[1]]
  if (length(rng) == 3) {
    a <- resolve_daytok(rng[2]); b <- resolve_daytok(rng[3])
    if (length(a) == 1 && length(b) == 1) return(expand_day_range(a, b))
  }
  toks <- regmatches(spec, gregexpr(DAYTOK, spec))[[1]]
  unique(unlist(lapply(toks, resolve_daytok)))
}

# --- the three format families ----------------------------------------------

# FAMILY A: per-day labeled lines -> "monday: 9:00 am - 7:00 pm"
parse_labeled <- function(s) {
  m <- gregexpr(paste0(DAYTOK, "\\s*:\\s*([^\n]*)"), s, perl = TRUE)
  hits <- regmatches(s, m)[[1]]
  if (length(hits) < 2) return(NULL)
  out <- lapply(hits, function(h) {
    p <- regmatches(h, regexec(paste0("^", DAYTOK, "\\s*:\\s*(.*)$"), h, perl = TRUE))[[1]]
    dd <- resolve_daytok(p[2]); body <- p[3]
    if (length(dd) == 0) return(NULL)
    if (grepl("closed", body)) {
      return(data.frame(day = dd, open_hour = NA_real_, close_hour = NA_real_,
                        is_open = FALSE, dusk = FALSE, multi = FALSE))
    }
    r <- extract_ranges(body); if (is.null(r)) return(NULL)
    data.frame(day = dd, open_hour = r$open_hour[1], close_hour = r$close_hour[1],
               is_open = TRUE, dusk = r$dusk[1], multi = nrow(r) > 1)
  })
  out <- do.call(rbind, Filter(Negate(is.null), out))
  if (is.null(out) || nrow(out) == 0) NULL else out
}

# FAMILY B: day-range prefixed segments -> "mon-fri 7:00am-12:00am sat-sun 7am-10pm"
parse_dayprefixed <- function(s) {
  # locate each day-spec, then take the first time range that follows it
  m <- gregexpr(paste0("(?:", DAYTOK, DAYCONNECT, DAYTOK, "|", SHORTRANGE_RE,
                       "|", DAYTOK, ")"), s, perl = TRUE)
  st <- m[[1]]; if (st[1] == -1) return(NULL)
  ln <- attributes(m[[1]])$match.length
  specs <- substring(s, st, st + ln - 1)
  bounds <- c(st[-1], nchar(s) + 1)
  out <- list()
  for (i in seq_along(specs)) {
    dd <- parse_day_spec(specs[i]); if (length(dd) == 0) next
    frag <- substring(s, st[i] + ln[i], bounds[i] - 1)
    if (grepl("^\\s*[:,-]?\\s*closed", frag)) {
      out[[length(out)+1]] <- data.frame(day = dd, open_hour = NA_real_,
        close_hour = NA_real_, is_open = FALSE, dusk = FALSE, multi = FALSE); next
    }
    r <- extract_ranges(frag); if (is.null(r)) next
    out[[length(out)+1]] <- data.frame(day = dd, open_hour = r$open_hour[1],
      close_hour = r$close_hour[1], is_open = TRUE, dusk = r$dusk[1], multi = nrow(r) > 1)
  }
  out <- do.call(rbind, out)
  if (is.null(out) || nrow(out) == 0) return(NULL)
  out[!duplicated(out$day), ]   # first spec mentioning a day wins
}

# FAMILY C: one range (or "24 hours") applying to all seven days
parse_uniform <- function(s) {
  if (grepl("24\\s*(hours|hrs|/7|hours a day)|open 24|always open", s)) {
    return(data.frame(day = DAYS, open_hour = 0, close_hour = 24,
                      is_open = TRUE, dusk = FALSE, multi = FALSE))
  }
  r <- extract_ranges(s); if (is.null(r)) return(NULL)
  data.frame(day = DAYS, open_hour = r$open_hour[1], close_hour = r$close_hour[1],
             is_open = TRUE, dusk = r$dusk[1], multi = nrow(r) > 1)
}

# --- main driver -------------------------------------------------------------
parse_hours_one <- function(raw) {
  s <- norm_hours(raw)
  if (is.na(s) || s == "") return(list(df = NULL, method = "blank"))
  for (fam in c("labeled", "dayprefixed", "uniform")) {
    d <- switch(fam,
                labeled      = parse_labeled(s),
                dayprefixed  = parse_dayprefixed(s),
                uniform      = parse_uniform(s))
    if (!is.null(d) && nrow(d) > 0) return(list(df = d, method = fam))
  }
  list(df = NULL, method = "unparseable")
}

parse_hours_table <- function(restrooms) {
  restrooms$facility_id <- seq_len(nrow(restrooms))
  rows <- list(); meth <- character(nrow(restrooms))
  for (i in seq_len(nrow(restrooms))) {
    p <- parse_hours_one(restrooms$hours_of_operation[i])
    meth[i] <- p$method
    if (!is.null(p$df)) {
      d <- p$df
      rows[[length(rows)+1]] <- data.frame(
        facility_id  = restrooms$facility_id[i],
        facility_name = restrooms$facility_name[i],
        day_of_week  = day_idx(d$day),
        open_hour    = d$open_hour,
        close_hour   = d$close_hour,
        is_open      = d$is_open,
        parsed       = TRUE,
        parse_method = p$method,
        dusk_assumed = d$dusk,
        multi_range  = d$multi)
    }
  }
  long <- bind_rows(rows)

  # --- repair obvious source am/pm typos ------------------------------------
  # e.g. a library listed "Tuesday: 10:00 pm - 6:00 pm" (open 10pm, close 6pm
  # next day = 20h). A pm open that yields a >14h day is an am/pm typo in the
  # SOURCE, not a real overnight facility. Flip the open to am and flag it.
  long$ampm_repaired <- FALSE
  fix <- !is.na(long$open_hour) & long$open_hour >= 12 &
         (long$close_hour - long$open_hour) > 14
  long$open_hour[fix]    <- long$open_hour[fix] - 12
  long$close_hour[fix]   <- long$close_hour[fix] - 24
  long$ampm_repaired[fix] <- TRUE

  # --- days a parsed facility never mentioned are treated as closed ---------
  seen <- long |> filter(parsed) |> distinct(facility_id, day_of_week)
  full <- expand_grid(facility_id = unique(seen$facility_id), day_of_week = 1:7)
  gaps <- anti_join(full, seen, by = c("facility_id", "day_of_week"))
  if (nrow(gaps)) {
    meta <- long |> filter(parsed) |> distinct(facility_id, facility_name, parse_method)
    long <- bind_rows(long, gaps |> left_join(meta, by = "facility_id") |>
      mutate(open_hour = NA_real_, close_hour = NA_real_, is_open = FALSE,
             parsed = TRUE, dusk_assumed = FALSE, multi_range = FALSE,
             ampm_repaired = FALSE, day_implied_closed = TRUE))
  }
  long$day_implied_closed[is.na(long$day_implied_closed)] <- FALSE
  # facilities that produced nothing still get a row per day, flagged unparsed
  failed <- setdiff(restrooms$facility_id, unique(long$facility_id))
  if (length(failed)) {
    fdf <- restrooms[restrooms$facility_id %in% failed, ]
    long <- bind_rows(long, expand_grid(
        facility_id = fdf$facility_id, day_of_week = 1:7) |>
      left_join(data.frame(facility_id = fdf$facility_id,
                           facility_name = fdf$facility_name,
                           parse_method = meth[failed]), by = "facility_id") |>
      mutate(open_hour = NA_real_, close_hour = NA_real_, is_open = NA,
             parsed = FALSE, dusk_assumed = NA, multi_range = NA,
             ampm_repaired = FALSE, day_implied_closed = NA))
  }
  attr(long, "method_by_facility") <- meth
  arrange(long, facility_id, day_of_week)
}

# --- run when sourced as a script -------------------------------------------
if (sys.nframe() == 0 || identical(environment(), globalenv())) {
  BASE <- Sys.getenv("RESTROOM_PROJ", unset = ".")   # run from the project root, or set RESTROOM_PROJ
  f <- list.files(file.path(BASE, "data_raw"), "^nycrestrooms_.*csv$", full.names = TRUE)[1]
  R <- read.csv(f)
  hrs <- parse_hours_table(R)
  meth <- attr(hrs, "method_by_facility")
  cat("facilities:", nrow(R), "\n"); print(table(meth))
  ok <- length(unique(hrs$facility_id[hrs$parsed]))
  cat(sprintf("\nparsed %d / %d facilities = %.1f%%\n", ok, nrow(R), 100*ok/nrow(R)))
  nb <- sum(trimws(R$hours_of_operation) != "" & !is.na(R$hours_of_operation))
  cat(sprintf("of the %d with non-blank hours: %.1f%%\n", nb, 100*ok/nb))
  cat("dusk-assumed facilities:", length(unique(hrs$facility_id[hrs$dusk_assumed %in% TRUE])), "\n")
  cat("multi-range facilities:", length(unique(hrs$facility_id[hrs$multi_range %in% TRUE])), "\n")
  cat("am/pm source typos repaired:", sum(hrs$ampm_repaired %in% TRUE), "rows on",
      length(unique(hrs$facility_id[hrs$ampm_repaired %in% TRUE])), "facilities\n")
  cat("day-rows implied closed (day absent from text):", sum(hrs$day_implied_closed %in% TRUE), "\n")
  cat("rows per facility:\n"); print(table(table(hrs$facility_id)))
  out <- file.path(BASE, "data_raw", paste0("parsed_hours_", format(Sys.Date(), "%Y%m%d"), ".csv"))
  write.csv(hrs, out, row.names = FALSE, na = "")
  cat("wrote", basename(out), nrow(hrs), "rows\n")
}
