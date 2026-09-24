# Trend stress test: "Parks restroom inspection failure 8.5% (2024) → 20.1% (2026)"

**Verdict: HOLDS WITH CAVEAT.**

The jump is real. It survives every artefact test I could run: seasonality, sample composition, inspectors, boroughs, concentration, time of day, snow and data-entry lag. The **level** is real. The **framing** is not. Three parts of the current story overstate the finding:

1. **The baseline is the lowest year on record.** Jan–Jun 2024 (8.5%) is the lowest of the 22 half-years available (2005–2026). 2026 (20.1%) is back at 2012–14 levels (21.2 / 17.0 / 20.0%). It is not unprecedented. It reverses a decade of improvement.
2. **About half the rise is not "decay" of anything we can see.** 5.4pp of the +11.6pp comes from restrooms marked **U with no sub-ratings at all**: nothing inside was rated. That most likely means the restroom was found closed or inaccessible [UNVERIFIED: the PIP coding manual is not in hand]. Only 6.1pp comes from failures where the inspector recorded an actual condition problem.
3. **"Structural quadruples" is the weakest claim.** Across all inspectors, structural U (including U/S) goes 5.9% → 19.2%, which is **×3.3, "triples"**. The ×4.8 "quadruples" comes only from the 7-inspector subset. A structural U now fails the whole restroom only 20–29% of the time, against 44–61% in 2018–22. So either minor defects are being flagged more, or the structural threshold drifted. The data cannot separate the two.

Also: in the overall rate the jump arrives as a **step at January 2026**, not a steady climb. Quarterly rates were 10–13.5% through 2025, then 19.3% and 20.9% in 2026. An earlier worklog entry said the series was "not a step, so not a rule revision". That was about the structural sub-score only, and it does not hold for the headline rate. A comfort-station-specific guidance change effective Jan 2026 cannot be ruled out from the data [OPEN].

Scripts are in this folder (`T1`–`T5`, read-only on `Restroom_Rebuild/data_raw/pip*`). Full output is in `T3_output.txt` and `T4_output.txt`.

---

## Reproduction

A/U-rated comfort-station inspections, Jan 1–Jun 28 (doy ≤ 179), `mp8v-wjtf` joined to `yg3y-7juh` (31,768 of 31,768 rows matched):

| | 2022 | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|
| n rated | 699 | 712 | 743 | 735 | 693 |
| fail | 9.4% | 9.0% | **8.5%** | 11.3% | **20.1%** |

- 95% CI, simple binomial: 2024 is 6.5–10.5% and 2026 is 17.1–23.1%. They do not overlap.
- Facility FE, SE clustered by facility, ref 2024: **+11.44pp (SE 2.00, p = 1e-8)**. A8 reports +11.35pp. The small gap comes from how facilities are defined: I use `prop_id` + `csnumber` (the comfort-station number), A8 uses `prop_id` only.

## Test 1: Seasonality (2026 covers only Jan–Jun)

The headline already compares Jan–Jun with Jan–Jun, so it is not a raw seasonal artefact. Further checks:

- **H1 series, 2005–2026:** 51.9, 36.5, 28.4, 28.6, 27.5, 21.8, 30.4, 21.2, 17.0, 20.0, 14.3, 16.2, 11.6, 14.8, 11.6, 12.7, 13.8, 9.4, 9.0, **8.5**, 11.3, **20.1**%. 2024 is the minimum. 2026 ranks 9th of 22 and is the highest since 2012.
- **Month-matched:** every month of 2026 is above the **maximum** of the same month in 2022–25. The margins are +2.3 (Jan), +15.4 (Feb), +2.7 (Mar), +5.9 (Apr), +16.2 (May) and +10.2pp (Jun). Jan and Mar are marginal.
- **Month-of-year FE plus facility FE**, all months 2018–2026: 2026 is **+10.2pp (SE 1.7)**.
- **Adjacent halves:** 2025 H2 is 11.9%, then 2026 H1 is 20.1%.
- **Baseline sensitivity:** 2024 H1 (8.5%) sits well below 2024 H2 (12.4%). Against the full year 2025 (11.6%), 2026 H1 is ×1.7, not ×2.4.

→ **Not seasonality. The choice of baseline inflates the ratio.**

## Test 2: Composition (which sites got inspected)

- SWEEP inspections in the restroom file (H1): 62 (2024), 97 (2025), 99 (2026). Almost none carry an A/U restroom rating.
- **Regular PIP only:** 8.5% → **19.9%**. FE +11.3pp (SE 2.0).
- **Balanced panel:** 395 facilities with a PIP restroom rating in H1 of *every* year 2022–26. The rate goes 9.3, 8.6, 5.9, 10.1, **18.1%**. FE **+11.9pp (SE 2.3, p = 3e-7)**. Weighting each facility once per year gives 5.7% → 17.8%.
- **First inspection per facility per year:** 9.4% (2024) → 19.7% (2026).

→ **Not composition.**

## Test 3: Rating-regime change

- **No new fields.** Fill rates of `safety_condition`, `structural_condition`, `inspector2`, `closed` and `visitorcount` are flat 2018–2026. Every restroom inspection has four sub-ratings or none, in every year. `comments` fill rises (16% → 32% in 2026), mostly from snow notes.
- **Inspectors.** 9 were active in 2026 H1, against 12 in 2024. Two are new in 2026: #63 fails 23.3% and #64 fails 11.5%.
  - Among returning inspectors, 6 of 7 rose from 2024 to 2026, for example #45 6.5% → 27.3%, #62 6.2% → 21.6% and #38 12.9% → 30.7%. #43 fell (11.4% → 7.2%).
  - Leave-one-inspector-out 2026 range: **18.8–21.8%**.
  - Facility FE plus inspector FE: **+11.1pp (SE 2.2)**.
- **Placebo at the whole-park level** (the master file only carries site-level `overall_condition` and `cleanliness`; per-feature ratings for other park features are not in `data_raw`):
  - Park properties with **no** comfort station: 10.2% (2024) → **9.6%** (2026), flat.
  - Cleanliness U across all PIP inspections: 6.4% → **6.8%**, flat.
  - **Same inspector, same period:** site-level fail at parks with no restroom stays flat while that inspector's restroom fail rate triples. #45 goes 7.9% → 8.3% (site) against 6.5% → 27.3% (restroom). #62 goes 7.6% → 8.1% against 6.2% → 21.6%. #61 goes 8.1% → 8.4% against 6.3% → 15.9%. #31 goes 12.0% → 12.4% against 7.1% → 23.5%.
  - **Not everything jumped. Only restrooms did.** A park-wide harsher-grading regime is ruled out.
- **Restroom sub-scores** (U or U/S share, H1, 2024 → 2026):

  | Sub-score | 2024 | 2026 | Reading |
  |---|---|---|---|
  | Litter | 2.1% | 2.2% | flat |
  | Graffiti | 0.3% | 1.0% | flat, tiny n |
  | Amenities | 7.4% | 9.5% | slight rise |
  | Structural | 5.9% | 19.2% | ×3.3 |

  Structural was already 7.6–7.9% in 2018–22, and it rises through 2023 (10.4%) and 2025 (13.6%).
- **Caution on structural.** P(overall U | structural U) was 61% (2018), 44% (2022), 20% (2024), 23% (2025) and 29% (2026). Structural U is being given far more often, and matters less. This is the pattern a lowered structural threshold would produce. It is also what more but milder defects would produce.
- **A comfort-station-only rule change dated Jan 2026 is not ruled out.** The quarterly overall rate is flat at ~10–13.5% for 2024Q3–2025Q4, then 19.3% (Q1) and 20.9% (Q2). The inspector-FE and within-inspector results do not exclude it, because a rule change applies to everyone. What would settle it: the PIP rating manual or guidance memos for 2025–26, or a direct question to NYC Parks Operations & Management Planning [OPEN].

## Test 4: Entry lag / later edits

- `inspaddeddate` is the same day as the inspection for 96–100% of rows in every year, with a maximum lag of 6 days. Nothing is back-filled late.
- Whether U ratings are **edited later** cannot be tested: the file is a single snapshot with no edit history [UNVERIFIED]. What would settle it: re-pull `mp8v-wjtf` in a few months and diff the 2026 H1 rows against the 20 Sep 2026 cache.

## Test 5: Closed / unrated share over time

| H1 | 2022 | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|
| N (unrated) share of all inspections | 23.1% | 27.0% | 22.1% | 25.9% | 28.8% |
| U with no sub-ratings, share of rated | 3.6% | 4.2% | 5.2% | 6.4% | **10.7%** |
| U with a condition sub-rating, share of rated | 5.9% | 4.8% | 3.2% | 4.9% | **9.4%** |
| Open and acceptable, share of all | 69.6% | 66.3% | 71.3% | 65.7% | **56.8%** |

- Separate FEs for the two components: no-sub-rating U is **+5.4pp (SE 1.5)** and condition U is **+6.0pp (SE 1.5)**. Both are significant.
- Worst case, counting N as a fail: 28.7% → 43.2%. The direction is unchanged.
- **Snow:** Feb 2026 comments are dominated by snow cover. Dropping Jan–Feb gives 2026 at 18.8% against 7.0% in 2024 for the same months.
- **Time of day:** 2026 inspections start earlier (8am share 6.6% → 12.8%). Re-weighting 2026 to the 2022–25 start-hour mix leaves no-sub-rating U unchanged at 10.7%, and the rate is higher in every hour.
- **Registry flags:** the rise sits in restrooms that are currently **not** winterized (4.5% → 11.0% no-sub-rating, 3.0% → 10.0% condition) and **not** in long-term closure.

→ **Not a coding shift from N to U.** But half the headline is "restroom not rated inside", not "restroom found broken".

## Test 6: Concentration (boroughs and parks)

- **By borough, H1 2024 → 2026:**

  | Borough | 2024 | 2026 |
  |---|---|---|
  | Brooklyn | 10.2% | 27.7% |
  | Manhattan | 10.9% | 22.5% |
  | Bronx | 6.4% | 20.5% |
  | Queens | 8.4% | 13.9% |
  | Staten Island | 0% | 4.3% (n ≈ 45) |

- **Leave-one-borough-out:** 2026 stays between **17.1% and 22.3%** whichever borough is dropped. Dropping Brooklyn gives the lowest figure.
- **Not a few sites:** 139 failures across **131 of 579 facilities**. The top 10 facilities hold 18 of them. Dropping the 8 facilities with 2 or more fails gives 8.6% → 18.2%.

→ **Broad-based.** Brooklyn, Manhattan and the Bronx carry it. Queens is weaker.

## Chart

`h1_failure_2012_2026.png` shows Jan–Jun failure 2012–2026, split into U with no sub-ratings and U with a condition sub-rating. It shows all three caveats at once: 2024 is the trough, 2026 is back at 2012–14 levels, and half of the rise is "not rated inside".

![](h1_failure_2012_2026.png)

## Wording for the presenter

**Safe:**
> "In the first half of 2026, one in five Parks restroom inspections failed. That's roughly double the rate in the same months of 2022–25, and back to where it was in 2012–14, after years of improvement. It shows up in the same buildings, in every borough, and across almost every inspector. Meanwhile the same inspectors' ratings of the rest of the park stayed flat. So it isn't the graders getting harsher across the board."

> "About half of those failures are restrooms the inspector couldn't rate inside, most likely found closed. The other half had a recorded problem, mostly structural."

> "Failure is observable; need is not." (Still fine.)

**Avoid:**
- "8.5% → 20.1%, the stock is decaying." The baseline is the record low, and half the rise is not an observed physical defect.
- "Structural failures quadrupled." Say "roughly tripled" (5.9% → 19.2%, all inspectors).
- "Worst ever", "unprecedented", "steadily worsening". The rate is at 2012–14 levels, and it moved as a step in Jan 2026 after 18 flat months.
- "Proves the buildings are deteriorating." Not proven: a comfort-station-specific rating change in 2026 is not excluded, and later edits are untestable.
- "Litter and graffiti are flat, so it's not the inspector." Say "the same inspectors rated the rest of the park no worse". That is the stronger and cleaner placebo.

## Open questions

1. What does overall U with all sub-ratings N mean in the PIP manual (closed during posted hours? locked?) [OPEN]. It drives half the rise.
2. Was there any PIP guidance change for comfort stations or structural ratings effective Jan 2026 (or during 2023, when structural U starts rising and decoupling from overall U) [OPEN]?
3. Are 2026 ratings revised later? Needs a second snapshot [UNVERIFIED].
4. Published `headline_numbers.json` uses the seven-inspector structural series (.044 → .210) behind "quadruples". The all-inspector figure (.059 → .192) is the safer one to quote.
