# City Criteria Model (started 26 Sep 2026)

**Current version (26 Sep, owner-approved): DEMAND minus SUPPLY** — scripts `R/01_features.R`, `R/05_gap.R`,
`R/06_gap_figures.R`. See `CHECKING.md` for run order and where every page number comes from.

## Current results (26 Sep, after ChatGPT audit: broken restrooms excluded from supply; see REVIEW_RESPONSE.md)
- Supply = listed operational AND scheduled open AND not flagged long-term closed / repeatedly failing (873 open at 2pm, 57 at 9pm).
- Pilot model M7: busyness +2.55 (1.35 to 3.79); distance 2pm +0.71 (0.08 to 1.46); 9pm +0.96 (0.19 to 1.84); equity +0.12
  (−0.37 to 0.52); plaza +1.61; street −2.13. AUC 0.91 (in-sample); LOO median 97%, mean 88%. Complaints −0.37 (−1.58 to 0.73).
- Demand weights 95/5. Top third 1,939 (MN 1,570, BK 186, BX 111, QN 72); contains 14 of 17 pilots (consistency check only).
- Supply coverage of candidates: 70% at 2pm, 16% at 9pm. Pilots 13/17 vs 1/17.
- Gap (pilots assumed operating): 1,246 (1,163 evening-only, 83 all-day). Pilots not operating: 1,357 / 162 existing / 25 new.
- Two-stage: 155 existing (105 park hours, 34 other operators, 16 repair AND keep open to 10pm) cover 1,183; 24 new units.
- Sensitivity: parks open to 10pm -> 396 / 37 / 24; top quarter 95 + 13; top half 344 + 76; 400 m 192 + 56; 8pm/10pm 150/162 existing,
  24 new. Random weights: existing 151–211 (median 180), new 16–38 (median 27); 103/155 kept exactly; 13/24 new-unit areas (500 m).
- Private supply: 32/18/2 (all outlets), 266/61/12 (late-night only), 451/91/14 (50% access).
- Residents: 69% at 2pm, 4% at 9pm; 761 existing (457 park, 207 other, 97 repair+hours) -> 73%; new 38/171/296/830 for 80/90/95/100%
  (greedy scenario, not a minimum). With the 24 fixed first: 75% start; 53/181/307/837 total.
- Overlap with 29 complaint areas: 3/17, 24/155, 2/24.

---

# Superseded: "next 50" version (02/02b/03 scripts; kept for the record). The one-stage 156-location version of 05 was also superseded (review #1).

The team's new direction after the professor meeting (25 Sep): learn which factors the City weighed when it sited the
17 modular pilot toilets, score every candidate site in the city on those factors, test the answer against many
weightings (professor: assumptions are fine *if* sensitivity shows the recommendation holds), then refine each site
with the "reality lens" from our earlier layered work (repair / longer hours / build).

## Where the factors come from — [VERIFIED] from the law text
Local Law 58 (2025) defines an *underserved area* as one with insufficient access "because of a lack of public bathrooms
**or limited opening hours**", considering "population density, estimated daily foot traffic, public transportation
routes, distance to existing public bathrooms ..., land use including current commercial and tourist corridors, and
equity concerns". Text saved at `Restroom_Rebuild/data_raw/ll58_2025_text_20260926.pdf` (from intro.nyc).
The pilot release (16 Sep) says the units go to "public plazas and high-traffic areas where New Yorkers currently lack
reliable access to a bathroom"; sites were chosen by DOT and Parks with NYCEDC. No weights are published anywhere.
Giorgia's four criteria (feasibility, biohazard, footfall, equity) have no source found — [ASSUMED] LLM-suggested.

## Scripts
| Script | Does |
|---|---|
| `R/01_features.R` | Measures six LL58 factors (+ 311 complaints) at 5,814 candidate sites and the 17 pilots |
| `R/02_revealed_weights.R` | Firth logistic: pilot (1) vs candidate (0); leave-one-pilot-out validation |
| `R/02b_robustness.R` | Site-type controls and a busyness index; saves the preferred model M4 |
| `R/03_score_sensitivity.R` | Scores sites (M4 weights), picks the next 50 (500 m spacing), 7 named + 2×2,000 random weightings, reality lens. `QUOTA=1` splits the 50 by borough population |

Factor measures: residents within 500 m; DOT modelled pedestrian demand (length × category) within 250 m; subway
entries within 500 m; jobs within 500 m; distance to nearest listed restroom open at 2pm; tract poverty rate.

## Results (26 Sep, final run; published in the site's "New direction" tab)
- Pilot sites vs typical candidate site (median percentile): residents 79, transit 75, poverty 73, foot traffic 72,
  complaints 70, jobs 68, distance to open restroom 58.
- First model (02, six factors entered separately): population took all the credit (foot traffic, jobs ~0) because the
  four busyness measures correlate 0.52-0.81. **Preferred model M4 (02b)**: busyness index (mean of the four) +
  distance + equity, with site-type controls. Standardised Firth coefficients: busyness +2.07 (0.98 to 3.20),
  distance +0.98 (0.27 to 1.81), equity +0.12 (-0.32 to 0.49); plaza +1.68, street -2.46 vs park.
  **Weights: busyness 65% (16% each part), distance 31%, equity 4%.** AUC 0.87.
- Complaints added (M6): -0.45 (-1.64 to 0.65), not significant -- no sign the City targeted complaint hotspots.
  (The earlier "-1.20, p = 0.05" was from the model without site-type controls; superseded.)
- Leave-one-pilot-out (M4): held-out pilot outranks a median 96% of candidates (range 41-100; weakest Fulton &
  Truxton 41, 34th Ave & 64th St 44, North Shore Esplanade 56, Northern Blvd & 54th St 60).
- Borough quota by population: Bronx 8, Brooklyn 15, Manhattan 10, Queens 14, Staten Island 3 (unconstrained: 36 of
  50 in Manhattan).
- Sensitivity: 41 of 50 locations picked in >=80% of 2,000 model-uncertainty draws (Test A). Test B, random weights
  over the three GROUPS (busyness / distance / equity): 20 of 50 picked in >=50% of runs; 18 pass both ("robust").
  (Random weights over the six factors gave 30 — superseded: they hand ~2/3 of the weight to the four correlated
  busyness measures on average; cold-read finding 26 Sep.) Chance baseline (random scores, same quotas and spacing):
  2% per location. Named scenarios keep 52-76% of locations.
- Evening-hours dependence: if the 641 placeholder-hours park restrooms already stay open to 10pm, 0 of the 14
  "longer park hours" sites has an evening gap -> all 14 depend on the 4pm assumption.
- Leave-one-out mean 84% (median 96%).
- Restroom checks (step 8): 23 build, 14 longer park hours, 8 repair/reopen, 4 other operator closes early, 1 already covered
  (26 served by a fix or longer hours nearby).
- Overlap with the 29 high-complaint neighbourhoods: 3 of 17 pilots, 5 of the 50.

## Caveats
17 cases; the weights say what the City *valued*, not proven need. Candidate pool includes large park interiors, which
inflates the population contrast. Straight-line distance; posted hours with the 4pm placeholder; residents-based
population. "Next 50" is an illustrative phase size, not a target.
