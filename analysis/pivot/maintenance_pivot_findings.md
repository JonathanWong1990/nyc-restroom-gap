# Maintenance pivot: tested results and a workable project flow

24 September 2026. This is a local feasibility study requested by the project owner.
It does not replace the published project or establish that repairs prevent failures.

## Decision

**Proceed with a narrower, evidence-backed project:**

> Can NYC use inspection history to target supplementary public-restroom maintenance
> checks more effectively?

The cached data is sufficient for this historical prediction study. It supports
prioritising sites for checks, not automatic reconstruction decisions, measured
repair ROI, a citywide new-toilet requirement, or guaranteed failures prevented.

The strongest result is that **simple inspection history is useful**. Logistic
regression performs similarly to a good three-year history rule. The project should
not claim that sophisticated modelling is essential or overwhelmingly better.

## The result that should lead

At each January/July planning date, select 20% of all eligible sites using only
previously available records. Freeze the model chosen using 2024 before evaluating
2025 H1, 2025 H2 and 2026 H1. There are 137 priority slots in each period, or 411
site-period slots altogether. These are repeated planning opportunities, not 411
distinct toilets or actual visits we carried out.

| Priority method | Subsequently recorded unacceptable outcomes in its list |
|---|---:|
| Random allocation, expected | 48.9 |
| Failure share in the last three rated inspections | 79.1 |
| Smoothed three-year failure history | 86.1 |
| Logistic regression selected on 2024 | 88.0 |

There are 244 recorded unacceptable outcomes across the eligible evaluation cohort.
The logistic list includes 36.1% of these while prioritising approximately 20% of
eligible sites. It includes about 1.8 times as many recorded failures as random
allocation, but only about two more than the three-year rule across all three periods.

**This is an observed-failure yield, not total precision:** 99 of the model's 411
selected site-periods have an unrated first visit or no follow-up. Their outcomes
remain unknown. A recorded unacceptable condition is also not a failure prevented.
Random allocation is a reference policy, not a claim about Parks' current actual
maintenance practice, and targeted checks should supplement independent random PIP
audits rather than replace them.

Source: `outputs/pooled_all_eligible_results.csv` and
`all_eligible_selection_metrics.csv`. Figure:
`outputs/all_eligible_priority_comparison.png`.

## What was actually tested

### Unit and data construction

- Original comfort-station table: 31,768 rows, 31,159 inspection IDs. Multiple
  comfort-station rows can belong to the same inspection. They are not independent
  inspections and the ordinal `csnumber` is not assumed to be a permanent asset ID.
- Join to inspection master is many-to-one, checked before use. Only regular `PIP`
  inspections enter the prediction study; SWEEP and other inspection types do not.
- Aggregate to inspection property (`prop_id`) and visit date. Any U means observed
  unacceptable; all A means acceptable; otherwise the outcome remains unknown.
- At each half-year start, require a prior visit within two years and at least one
  rated observation in the preceding three years.
- Features use records with both inspection date and record-entry date before the
  planning date. No future condition subscore, visitor count, inspector identity,
  current closure status, or current inventory condition enters the forecast.
- Outcome is the **first regular visit in that half-year**, if it has a usable A/U
  rating. We do not skip an unrated first visit to find a later favourable label.
- Sites without a follow-up visit or with an unrated first visit remain in the
  eligibility audit. Their missing labels are not converted into passes.

### Temporal separation

| Stage | Period | Rated site-period outcomes | Unacceptable |
|---|---|---:|---:|
| Development | 2018–2023 | 6,579 | 777 |
| Model selection | 2024 | 1,170 | 130 |
| Held-out evaluation | 2025 and January–June 2026 | 1,685 | 244 |

The held-out rated sample comprises 644 inspection properties in 516 parent parks.
These are repeated observations of an existing network, not a test on entirely new
parks. That matches the maintenance decision. Inspection history before 2018 can
contribute to predictors of the earliest training rows.

Two logistic specifications and four shallow classification-tree configurations were
compared with five baseline/rule variants. Selection used top-20% precision in 2024,
with Brier score as a tie-breaker. The selected logistic model uses last rated result,
failure share in the last three rated visits, elapsed time, borough, and half-year.
It was refitted through 2024 and kept fixed for all held-out periods.

The three-year benchmark uses `(failures + 0.5) / (rated visits + 5)` over prior
three-year history. This modest fixed smoothing avoids giving short histories
extreme scores. It was among the benchmarks specified before performance was known;
it was weaker in 2024 but matched the logistic model in the later holdout. It has not
been selected retrospectively and represented as the original validation winner.

Tied scores receive fractional allocation at the capacity cutoff. For example,
selecting part of a tied group credits the expected number of outcomes under random
selection within that tie. That is why baseline counts are fractional.

### Complete-outcome comparison, for teaching precision and recall

As a separate calculation, restrict the ranking universe to the sites whose first
visit is rated, then select 20% within each period. This is a conditional evaluation,
not the full deployment policy above.

| Method | Priority slots | Recorded failures captured | Precision | Recall |
|---|---:|---:|---:|---:|
| Random, expected | 338 | 48.9 | 14.5% | 20.0% |
| Last-three rule | 338 | 83.7 | 24.8% | 34.3% |
| Three-year rule | 338 | 92.2 | 27.3% | 37.8% |
| Logistic | 338 | 92.0 | 27.2% | 37.7% |

Do not mix the 338-slot conditional table with the 411-slot all-eligible table.
Do not call either table the result of an actual intervention.

## Robustness, limitations, and results that did not match the initial hope

1. **Model advantage is modest.** In the all-eligible analysis, the parent-park
   cluster-bootstrap 95% interval for logistic minus three-year-rule known-failure
   yield is approximately **−2.3 to +3.3 percentage points**. No convincing superiority
   over that rule. Against the validation-selected last-three rule the interval is
   about +0.1 to +3.8 points. These are conditional on the fitted models and historical
   period, not uncertainty about every possible deployment environment.
2. **The ranking is useful but imperfect.** Logistic ROC AUC is 0.615, 0.658 and 0.643
   in the three held-out periods. With a 20% budget, most observed unacceptable
   outcomes still fall outside the priority list. Keep broad monitoring.
3. **Probability calibration drifts.** For 2026 H1 the model predicts an average
   11.7% failure rate among rated outcomes; actual is 20.2%. The ranking retains
   value, but the scores must not be presented as reliable current probabilities.
   No retrospective recalibration was used to improve the reported test results.
4. **Outcomes are selectively missing.** Of 2,050 eligible test site-periods, 1,685
   are rated, 324 have an unrated first visit, and 41 have no visit. Thus 17.8% lack a
   usable outcome. Their average model risk is generally higher, not lower, than
   rated sites. Missing outcomes cannot be assumed to be random. The all-eligible
   analysis reports both observed yield and worst/best bounds for missing labels.
5. **The story is not uniquely prediction of brand-new problems.** Among sites
   whose last rated inspection passed, history still concentrates subsequent
   failures, but logistic does not consistently beat the last-three rule. Do not
   claim it reliably spots deterioration before any prior warning.
6. **More input fields did not win.** The larger logistic model with previous
   structural, amenity and litter subscores did not win validation. The imagined
   claim that structural warnings are the key predictor is not supported by this
   run. The four tested classification trees collapsed to stumps; that is a result
   for these configurations, not proof that all tree methods are ineffective.
7. **Capacity matters.** In the conditional top-50-per-period comparison, logistic
   captures 48 outcomes versus 46.7 for the last-three rule and 22.0 for random.
   The advantage over a good rule is especially small at that budget. 10%, 20%, 30%
   and top-50 results are all saved, not just the most attractive capacity.
8. **Not driven solely by huge parks.** Excluding the five largest parent-park
   clusters preserves the logistic-versus-random/last-three pattern in all periods.
9. **No measured treatment benefit.** The analysis predicts later recorded
   condition under historical practice, which already includes maintenance. It
   does not measure natural deterioration without maintenance, causal repair
   effects, daily uptime, avoided closures, or dollars saved.
10. **Data dates limit deployment.** Inspections end on 28 June 2026. The final list
    is explicitly an illustrative 1 July 2026 planning snapshot, not a verified
    September work order. Only Parks inspection sites are covered.

## What happens to the complaint work?

It remains context and was tested as an optional predictor. The exploratory
extension used address-month-deduplicated public-space urination complaints within
400 metres of exactly matched restroom structures, filed during the preceding 365
days. Only structures with known pre-2020 construction dates entered the extension;
both models use the same matched sample and 2021–2024 training window.

There are 1,267 matched rated holdout site-periods, with 189 unacceptable outcomes.
Using 254 top-20% slots across the three periods:

- History model alone captures **67** unacceptable outcomes.
- Adding nearby past complaints captures **68**.
- Complaint counts alone capture **42.7 expected** outcomes.

This particular complaint measure offers negligible practical improvement. That is
not a universal claim that complaints contain no information, and the extension is
exploratory on the same holdout rather than an independent new confirmation. Its
result does support moving complaints out of the maintenance-ranking engine.

## Does the access analysis still connect?

Yes, as a **current context layer with a limited verified join**, not a prediction
of lost service or a reason to add arbitrary weights.

Of 682 illustrative July planning sites:

- 531 match exactly one geocoded restroom structure by inspection-site ID.
- 514 have an unambiguous one-to-one proximity match to the cached public inventory.
- 487 of those are listed operational in that inventory.
- 282 of the 514 have no other listed operational facility within 400 metres
  straight-line distance. This includes some currently listed non-operational
  focal facilities; it is not a count of 282 working toilets at imminent risk.

Distances do not establish walking time or opening-hour availability, and a register
match is not an on-site verification. The register is an older snapshot. Example:
Wayanda Park appears in the high-ranked illustrative list and its nearest other
listed operational facility is about 1,007 metres away straight-line. This is a
reason to verify alternatives and current condition, not proof it will close or a
recommendation for a particular capital project.

The structures table has 60 missing `doitt_id` values on distinct buildings;
`system` is the unique asset key. None were collapsed as duplicate missing IDs.

## The confirmed presentation flow (12 minutes)

1. **Context — dependable service matters (1 minute).** Retain one access map and
   brief complaint context. Introduce the existing inspection deterioration finding
   as the reason to examine current stock. Avoid claiming complaints prove the need
   for a new facility.
2. **A decision NYC can actually make (1 minute).** Where should limited
   supplementary maintenance checks go? Audience: Parks operations managers. Keep
   independent random inspections for accountability and population monitoring.
3. **An observable target and fair test (2 minutes).** Show inspection history,
   acceptable/unacceptable/unknown states, and the 2018–2023 / 2024 / 2025–2026 split.
   Explain that all inputs pre-date the decision.
4. **Do the methods improve prioritisation? (3 minutes).** Show the all-eligible
   49 / 79 / 86 / 88 comparison. Use the conditional precision/recall table only if
   teaching metrics is helpful. Explain that much of the benefit comes from a simple
   history rule, not machine-learning sophistication.
5. **What the evidence rules out (2 minutes).** Complaints add almost nothing in the
   tested extension; extra condition fields do not win; risk levels drift in 2026;
   some outcomes remain unknown. These limits directly shape the recommendation.
6. **A practical operating recommendation (3 minutes).** Use a transparent history
   rule or the validated logistic ranking to schedule additional checks; verify
   unresolved/unrated sites; show nearby alternatives as context; refresh data and
   monitor calibration. Record action dates, work done and follow-up condition so a
   future study can test whether the targeting actually improves service.

**Proposed closing claim:** "Inspection history can help NYC concentrate additional
maintenance checks where unacceptable restroom conditions are more likely to be
recorded. A simple rule captures most of the benefit. The city must still verify
unobserved conditions and measure whether targeted maintenance improves service."

Course fit: descriptive statistics and uncertainty; logistic regression; decision
trees and model comparison; precision/recall and resource-constrained decisions;
spatial context; prediction-versus-causation. A repair-effect DiD is not required to
make this project complete and has not been established by this analysis.

## Data sufficiency

| Component | Status |
|---|---|
| Historical prediction and rule comparison | Sufficient; executed and checked |
| Complaint extension | Sufficient for the defined matched subset; executed |
| Spatial context | Partial; 514/682 unambiguous inventory matches |
| Current field-ready maintenance list | Not established; stale inputs and missing outcomes require verification |
| Causal effect of maintenance / repair ROI | Not established; action histories and credible evaluation needed |
| Citywide need for new toilets | Not answered by this pivot |

## Reproduce and inspect

From `Final Project/Maintenance_Pivot_Feasibility/` (reads data from `../Restroom_Rebuild/data_raw/`):

```sh
Rscript R/M1_maintenance_feasibility.R
Rscript R/M2_maintenance_context.R
Rscript R/M3_maintenance_verification.R
```

All outputs are in this folder's `outputs/`. Inputs are read-only
cached files; no downloads or public-site changes. The pre-performance protocol is
`notes/maintenance_pivot_protocol.md`. Input MD5s and R session information are saved.

Useful files: `pooled_all_eligible_results.csv`, `pooled_heldout_results.csv`,
`all_eligible_selection_metrics.csv`, `all_eligible_bootstrap_ci.csv`,
`validation_selection.csv`, `cohort_coverage.csv`, `period_calibration.csv`,
`complaint_extension_metrics.csv`, `priority_list_with_spatial_context.csv`, and
`verification.txt`. Model predictions and intermediate visit/panel data are retained
for inspection. No reported predictive gain was obtained by tuning on test outcomes.
