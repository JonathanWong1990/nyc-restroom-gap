# geo_helpers.R -----------------------------------------------------------
# Shared utilities for the NYC Restroom Gap rebuild.
# source() this from any workstream script:
#   source(file.path(PROJ, "R", "geo_helpers.R"))
#
# Provides:
#   socrata_get()     paged Socrata pull w/ $order=:id, backoff, disk cache
#   load_geo()        read a saved boundary GeoJSON, force EPSG:4326
#   points_to_area()  tag a lat/lon data frame with the area ID (st_join)
#   areal_crosswalk() area-weighted overlap weights between two polygon sets
#
# Conventions enforced here (see CONVENTIONS.md):
#   options(scipen=999) so $offset is never sent as 1e+05
#   $order=:id on every page so offset paging is stable
#   cache-first: if the file exists on disk we read it, we do not re-pull
# -------------------------------------------------------------------------

options(scipen = 999, stringsAsFactors = FALSE)

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(sf)
})

# Project root: the folder that contains R/, data_raw/, notes/.
# Override by setting RESTROOM_PROJ before sourcing.
if (!exists("RESTROOM_PROJ")) {
  RESTROOM_PROJ <- normalizePath(
    file.path(dirname(sys.frame(1)$ofile %||% "."), ".."),
    mustWork = FALSE
  )
}
`%||%` <- function(a, b) if (is.null(a)) b else a

NYC_CRS_WGS84 <- 4326   # lat/lon, what Socrata serves
NYC_CRS_FEET  <- 2263   # NAD83 / New York Long Island (ftUS) -- use for area/distance

# --- 1. Socrata paged pull ------------------------------------------------
#' Pull an entire Socrata dataset, page by page, with caching.
#'
#' @param dataset_id  e.g. "63ge-mke6"
#' @param domain      "data.cityofnewyork.us" (default) or "data.ny.gov"
#' @param cache_file  path to an .rds cache. If it exists, it is read and
#'                    NOTHING is downloaded.
#' @param select      optional $select clause (character scalar)
#' @param where       optional $where clause (character scalar)
#' @param page_size   rows per request (Socrata hard-caps at 50000)
#' @param max_rows    stop after this many rows (NULL = all)
#' @param app_token   optional Socrata app token (raises rate limit)
#' @param sleep       seconds between pages
#' @return data.frame
socrata_get <- function(dataset_id,
                        domain     = "data.cityofnewyork.us",
                        cache_file = NULL,
                        select     = NULL,
                        where      = NULL,
                        page_size  = 25000,
                        max_rows   = NULL,
                        app_token  = Sys.getenv("SOCRATA_APP_TOKEN"),
                        sleep      = 1.5,
                        verbose    = TRUE) {

  options(scipen = 999)   # belt and braces: must be set before offsets are pasted

  if (!is.null(cache_file) && file.exists(cache_file)) {
    if (verbose) message("[cache] ", basename(cache_file))
    return(readRDS(cache_file))
  }

  url  <- sprintf("https://%s/resource/%s.json", domain, dataset_id)
  hdrs <- if (nzchar(app_token)) add_headers(`X-App-Token` = app_token) else add_headers()

  out <- list(); offset <- 0L; page <- 0L
  repeat {
    lim <- page_size
    if (!is.null(max_rows)) lim <- min(lim, max_rows - offset)
    if (lim <= 0) break

    q <- list(`$limit` = format(lim, scientific = FALSE),
              `$offset` = format(offset, scientific = FALSE),
              `$order` = ":id")                      # NON-NEGOTIABLE: stable paging
    if (!is.null(select)) q[["$select"]] <- select
    if (!is.null(where))  q[["$where"]]  <- where

    # retry with exponential backoff
    resp <- NULL
    for (attempt in 1:5) {
      resp <- try(GET(url, query = q, hdrs, timeout(180)), silent = TRUE)
      if (!inherits(resp, "try-error") && status_code(resp) == 200) break
      wait <- 2^attempt
      code <- if (inherits(resp, "try-error")) "ERR" else status_code(resp)
      if (verbose) message("  retry ", attempt, " (", code, ") sleeping ", wait, "s")
      Sys.sleep(wait)
    }
    if (inherits(resp, "try-error") || status_code(resp) != 200)
      stop("Socrata failed on ", dataset_id, " at offset ", offset)

    txt <- content(resp, as = "text", encoding = "UTF-8")
    df  <- fromJSON(txt, flatten = TRUE)
    if (length(df) == 0 || (is.data.frame(df) && nrow(df) == 0)) break

    page <- page + 1L
    out[[page]] <- df
    n <- nrow(df)
    offset <- offset + n
    if (verbose) message("  page ", page, ": ", n, " rows (total ", offset, ")")
    if (n < lim) break
    Sys.sleep(sleep)
  }

  res <- if (length(out) == 0) data.frame() else do.call(rbind, lapply(out, as.data.frame))
  if (!is.null(cache_file)) {
    dir.create(dirname(cache_file), showWarnings = FALSE, recursive = TRUE)
    saveRDS(res, cache_file)
  }
  res
}

# --- 1b. Socrata boundary (GeoJSON) pull ----------------------------------
#' Download a Socrata geospatial dataset straight to a .geojson file on disk.
#' Cache-first: if `out_path` exists it is just read back.
socrata_geojson <- function(dataset_id, out_path,
                            domain = "data.cityofnewyork.us",
                            limit = 50000, verbose = TRUE) {
  options(scipen = 999)
  if (!file.exists(out_path)) {
    url <- sprintf("https://%s/resource/%s.geojson", domain, dataset_id)
    dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
    ok <- FALSE
    for (attempt in 1:5) {
      r <- try(GET(url,
                   query = list(`$limit` = format(limit, scientific = FALSE),
                                `$order` = ":id"),
                   write_disk(out_path, overwrite = TRUE), timeout(300)),
               silent = TRUE)
      if (!inherits(r, "try-error") && status_code(r) == 200) { ok <- TRUE; break }
      Sys.sleep(2^attempt)
    }
    if (!ok) stop("GeoJSON download failed: ", dataset_id)
    if (verbose) message("[pulled] ", basename(out_path), " ",
                         round(file.size(out_path) / 1e6, 2), " MB")
  } else if (verbose) message("[cache] ", basename(out_path))
  load_geo(out_path)
}

# --- 2. Boundary loader ---------------------------------------------------
#' Read a boundary file and guarantee EPSG:4326 + valid geometry.
load_geo <- function(path, quiet = TRUE) {
  g <- sf::st_read(path, quiet = quiet)
  if (is.na(sf::st_crs(g))) sf::st_crs(g) <- NYC_CRS_WGS84
  if (sf::st_crs(g)$epsg %||% 0 != NYC_CRS_WGS84) g <- sf::st_transform(g, NYC_CRS_WGS84)
  g <- sf::st_make_valid(g)
  g
}

# --- 3. Point tagging -----------------------------------------------------
#' Tag a lat/lon data frame with the polygon it falls in.
#'
#' @param df       data frame with numeric lat/lon columns
#' @param areas    sf polygons (e.g. the census tract file)
#' @param lon_col,lat_col  column names in df
#' @param area_id  column(s) of `areas` to attach (default "geoid")
#' @param keep_unmatched  TRUE keeps rows that fell outside NYC (area_id = NA)
#' @return the ORIGINAL df (non-sf) plus the area_id column(s) and
#'         attribute "unmatched" = n rows that fell outside every polygon.
points_to_area <- function(df, areas,
                           lon_col = "longitude", lat_col = "latitude",
                           area_id = "geoid",
                           keep_unmatched = TRUE) {

  stopifnot(all(c(lon_col, lat_col) %in% names(df)))
  df[[lon_col]] <- suppressWarnings(as.numeric(df[[lon_col]]))
  df[[lat_col]] <- suppressWarnings(as.numeric(df[[lat_col]]))

  df$.row_id <- seq_len(nrow(df))
  ok <- is.finite(df[[lon_col]]) & is.finite(df[[lat_col]])
  n_nocoord <- sum(!ok)

  pts <- sf::st_as_sf(df[ok, , drop = FALSE],
                      coords = c(lon_col, lat_col),
                      crs = NYC_CRS_WGS84, remove = FALSE)

  areas <- sf::st_make_valid(areas)
  if (sf::st_crs(areas) != sf::st_crs(pts)) areas <- sf::st_transform(areas, NYC_CRS_WGS84)

  keep <- intersect(area_id, names(areas))
  if (!length(keep)) stop("area_id not found in `areas`: ", paste(area_id, collapse = ", "))

  old_s2 <- sf::sf_use_s2(); on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  sf::sf_use_s2(FALSE)
  j <- suppressMessages(
    sf::st_join(pts, areas[, keep], join = sf::st_intersects, left = TRUE))
  j <- sf::st_drop_geometry(j)
  # a point on a shared border can match 2 polygons -> keep the first
  j <- j[!duplicated(j$.row_id), , drop = FALSE]

  res <- merge(df, j[, c(".row_id", keep)], by = ".row_id", all.x = TRUE, sort = FALSE)
  res <- res[order(res$.row_id), , drop = FALSE]
  res$.row_id <- NULL

  n_unmatched <- sum(is.na(res[[keep[1]]]))
  if (!keep_unmatched) res <- res[!is.na(res[[keep[1]]]), , drop = FALSE]

  attr(res, "unmatched")   <- n_unmatched
  attr(res, "no_coords")   <- n_nocoord
  message(sprintf("points_to_area: %d rows in, %d without coords, %d outside all polygons (%.1f%% matched)",
                  nrow(df), n_nocoord, n_unmatched,
                  100 * (nrow(df) - n_unmatched) / max(nrow(df), 1)))
  rownames(res) <- NULL
  res
}

# --- 4. Area-weighted crosswalk ------------------------------------------
#' Overlap weights between two polygon layers (e.g. taxi zones -> tracts).
#' Returns one row per (from, to) pair with w_from = share of the FROM
#' polygon's area sitting inside the TO polygon (sums to ~1 per from-unit).
areal_crosswalk <- function(from, to, from_id, to_id, crs = NYC_CRS_FEET) {
  old_s2 <- sf::sf_use_s2(); on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  sf::sf_use_s2(FALSE)

  f <- sf::st_make_valid(sf::st_transform(from[, from_id], crs))
  t <- sf::st_make_valid(sf::st_transform(to[,   to_id  ], crs))
  f$.from_area <- as.numeric(sf::st_area(f))

  ix <- suppressWarnings(sf::st_intersection(f, t))
  ix <- ix[!sf::st_is_empty(ix), ]
  ix$.ov_area <- as.numeric(sf::st_area(ix))
  ix <- sf::st_drop_geometry(ix)
  ix <- ix[ix$.ov_area > 0, ]
  ix$w_from <- ix$.ov_area / ix$.from_area
  ix[order(ix[[from_id]], -ix$w_from), ]
}

invisible(TRUE)
