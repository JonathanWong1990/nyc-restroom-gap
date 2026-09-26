# Review findings — City Criteria Model

Reviewed: 26 September 2026

## Scope and overall assessment

Reviewed `CHECKING.md`, `README.md`, the current feature and gap scripts (`R/01_features.R` and `R/05_gap.R`), and saved analysis objects. Per `CHECKING.md`, the superseded “next 50” analysis and frozen deck outline were excluded. The published website could not be retrieved for comparison.

The demand-versus-supply structure is clear, and the saved headline results are internally consistent. However, the proposed intervention mix does not reproduce the coverage of the hypothetical selected locations. Correct that issue and the demand-score scaling before presenting the intervention count as final.

This was a code and saved-results review, with independent spatial coverage checks. It was not a full rebuild from raw data or verification of every external source. No existing analysis files were changed.

## Verified results

Checks using `cache/features.rds`, `cache/gap.rds`, and `../Build_Plan/prototype/cache/prep.rds` confirmed:

| Measure | Verified result |
|---|---:|
| Base-case gap points | 1,249 |
| Selected hypothetical locations | 156 |
| Gap points left uncovered by those 156 locations at 500 m | 0 |
| Borough counts | Manhattan 68; Brooklyn 36; Bronx 27; Queens 25 |
| First-action labels | Park hours 101; repair/reopen 27; other operator hours 12; build 16 |
| Extended placeholder park hours to 10 pm, evaluated at 9 pm | 355 gap points; 46 locations |
| Leave-one-pilot-out percentile | Median 95; mean 87.41 |
| Random-weight location counts | 150–225; median 182 |
| Settings scenarios | 36 |
| Stability counts | 127 pass weight threshold; 131 pass settings threshold; 109 pass both |
| Mean chance-baseline area hit rate | 33.78% |

These checks reproduce saved results; they do not establish that the assumptions or recommended interventions are valid.

## 1. High priority: nearby fixes do not preserve selected-location coverage

**Code:** `R/05_gap.R`, lines 75–112.

The greedy algorithm covers gap points by placing hypothetical units at candidate coordinates. The subsequent first-action classification substitutes repair/reopening or longer hours at facilities within 500 m of each selected coordinate. Those facilities have different coordinates and therefore different coverage. Being close to a selected location does not ensure that a facility covers the demand points assigned to that location.

An independent spatial check activated every eligible facility corresponding to the recommended action categories, plus the 16 selected new-unit locations:

- For repair/reopen rows: all nearby facilities flagged by the script's repair/reopen rule.
- For park-hours rows: all nearby daytime-only facilities with placeholder park hours.
- For other-hours rows: all nearby eligible daytime-only facilities.
- For build rows: the selected candidate coordinates.

Even this optimistic scenario, comprising **187 unique existing facilities plus 16 new units**, leaves **103 of the original 1,249 gap points uncovered** within 500 m.

**Recommendation:** Treat the current action labels as investigation priorities. To produce an implementable intervention mix, use actual existing-facility coordinates for repairs and extensions, candidate coordinates for new units, and rerun selection and coverage. Deduplicate existing facilities so one repair is not counted as multiple interventions. Include feasibility and cost when available.

## 2. High priority: demand-score scaling differs from model fitting

**Code:** `R/05_gap.R`, lines 29–30, 49–56, and 70.

The pilot model uses a restandardised busyness composite: the mean of four standardised features is itself centred and divided by its standard deviation. Candidate demand scoring applies the fitted coefficient weights to the four-feature mean without that second transformation. Pilot demand scoring uses the same unadjusted form.

The standard deviation of the fitting-data busyness mean is **0.8764486**, rather than 1. Consequently, the relative contribution of busyness versus equity in the applied score differs from the fitted demand terms. Ranking the result into percentiles does not remove this relative-weight mismatch.

**Recommendation:** Apply the fitting-data composite transformation consistently to baseline candidate and pilot scores. Explicitly define the intended scaling for alternative composites in sensitivity scenarios. Rerun rankings, gap selection, figures, and reported counts after correction; the impact on the final counts has not yet been measured.

## 3. Interpretation: estimated associations are not the City's actual weights

**Code:** `R/05_gap.R`, lines 32–50; related interpretation in `README.md`.

The model relates measured features to 17 pilot locations versus the chosen candidate comparison pool. It does not identify the City's actual decision process or prove that the coefficients measure underlying restroom need. Unmeasured feasibility, the construction of the candidate pool, and other siting constraints can affect the associations.

The 95% busyness / 5% equity split is a normalised, nonnegative transformation of fitted coefficients used for scoring. Equity's reported confidence interval crosses zero.

**Recommendation:** Describe these as “model-derived scoring weights based on associations with pilot selection.” Avoid statements that the analysis establishes what the City valued or its true weighting of equity.

The reported AUC is calculated on the fitting data. The leave-one-pilot-out result is a held-out pilot's percentile against controls used in that fold's training; it is a separate measure, not an independently validated AUC or an accuracy percentage. Report these distinctions plainly.

## 4. Decision sensitivity: park opening hours dominate the count

**Code:** `R/05_gap.R`, lines 60–62 and 125–127.

At the baseline threshold and 500 m radius, changing the assumed closing time for placeholder-hours parks from 4 pm to 10 pm reduces the 9 pm gap from **1,249 to 355 points** and the selected count from **156 to 46 locations**. The location count falls by approximately **71%**.

**Recommendation:** Make this a central finding in the presentation. Verify actual opening hours before committing to an intervention count. Present 156 and 46 as conditional scenario results, rather than treating 156 as a settled citywide requirement.

The greedy algorithm supplies a feasible cover of the discretised gap points under the stated assumptions; it does not prove the minimum number of locations, coverage of all residents, walking-route access, or sufficient restroom capacity.

## 5. Reporting: stability is measured at area level

**Code:** `R/05_gap.R`, lines 117–130 and 137–140.

A baseline location receives a sensitivity “hit” whenever any scenario-selected location falls within 500 m of it. The identical candidate need not be selected, and one scenario location can count as a hit for more than one baseline location. The comparison remains at 500 m even for scenarios using a 400 m service radius.

**Recommendation:** Use “area-level stability within 500 m,” rather than implying exact-site retention. Explain the hit definition beside the stability figures and distinguish it from the service-radius setting.

## Suggested presentation conclusion

> The model identifies priority areas for evening restroom access. Verifying opening hours and optimising interventions at actual repair, extension, and construction locations are necessary before specifying the final intervention count.

## Recommended next steps

1. Correct and rerun the baseline demand-score scaling.
2. Recalculate coverage using actual intervention locations, deduplicating existing facilities.
3. Update the counts and figures from that revised analysis.
4. State opening-hours scenarios prominently and label model associations, validation measures, and area-level stability precisely.
