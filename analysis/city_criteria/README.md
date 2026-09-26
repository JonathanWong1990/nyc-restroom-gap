# City Criteria Model (started 26 Sep 2026)

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
- Sensitivity: 41 of 50 locations picked in >=80% of 2,000 model-uncertainty draws; 30 of 50 also in >=50% of 2,000
  random-weight draws. Named scenarios keep 52-76% of locations.
- Reality lens: 23 build, 14 longer park hours, 8 repair/reopen, 4 other operator closes early, 1 already covered.
- Overlap with the 29 high-complaint neighbourhoods: 3 of 17 pilots, 5 of the 50.

## Caveats
17 cases; the weights say what the City *valued*, not proven need. Candidate pool includes large park interiors, which
inflates the population contrast. Straight-line distance; posted hours with the 4pm placeholder; residents-based
population. "Next 50" is an illustrative phase size, not a target.
