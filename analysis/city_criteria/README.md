# City Criteria Model (started 26 Sep 2026)

**Current version (26 Sep, owner-approved): DEMAND minus SUPPLY** — scripts `R/01_features.R`, `R/05_gap.R`,
`R/06_gap_figures.R`. See `CHECKING.md` for run order and where every page number comes from.

## Current results (05_gap.R, revised 26 Sep after REVIEW_FINDINGS.md)
- Pilot model M7 (Firth logistic, 17 pilots vs 5,756 candidates, site-type controls): busyness +2.60 (1.39 to 3.84),
  distance to restroom open at 2pm +0.78 (0.13 to 1.56), at 9pm +0.96 (0.19 to 1.84), equity +0.13 (−0.36 to 0.53);
  plaza +1.58, street −2.20. In-sample AUC 0.91; leave-one-out median 95%, mean 87%. Complaints added: −0.38 (−1.59 to 0.72).
  These are associations with pilot selection, not the City's decision rule.
- Model-derived demand weights: busyness 95%, equity 5%; busyness composite re-standardised with fitting-data mean/sd
  before weighting (review #2). Top third of demand = 1,939 sites (1,570 Manhattan); contains 14 of 17 pilots.
- Supply (500 m): 71% of candidates covered at 2pm, 16% at 9pm. Pilots: 13/17 covered at 2pm, 1/17 at 9pm.
- Gap = top-third demand AND nothing open within 500 m at 9pm (not within 500 m of a pilot): 1,247 (1,182 evening-only, 65 all-day).
- Two-stage cover (review #1): stage 1 existing restrooms at their own coordinates -> 154 (103 park hours to 10pm,
  35 other operators' hours, 16 repair/reopen), covering 1,183 of 1,247; stage 2 new units -> 24. First 25/50/100
  existing restrooms cover 56/74/89%. Independent check in script: every gap site covered.
- Scenarios: parks already open to 10pm -> gap 355, 29 existing (28 other hours, 1 repair), 24 new units.
  Top quarter 97 + 13; top half 344 + 76; 400 m 191 + 56; 8pm/10pm 149/161 existing, 24 new.
- Random demand weights (200): existing 151–211 (median 180), new 16–38 (median 27); 103/154 existing restrooms kept
  exactly in >=80% of runs; 13/24 new-unit areas kept (within 500 m, area-level) in >=80%.
- Overlap with the 29 high-complaint neighbourhoods: 3/17 pilots, 24/154 existing, 2/24 new.
- Private toilets (07, sub-agent, 26 Sep): chain outlets as supply -> new units 2 (all outlets open to all at 9pm) /
  12 (late-night fast food only at 9pm) / 14 (same, 50% access); see PRIVATE_SUPPLY_FINDINGS.md.
- Residents (09): 72% covered at 2pm, 4% at 9pm; 761 existing restrooms (457 park hours, 207 other, 97 repair) bring
  9pm to 73%; new units anywhere residents live: 38 -> 80%, 171 -> 90%, 296 -> 95%, 830 -> 100%. Same order as LL58's
  1,145; steep diminishing returns. (08: covering every CANDIDATE site needs 443 + 231 but reaches only 56% of residents.)

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
