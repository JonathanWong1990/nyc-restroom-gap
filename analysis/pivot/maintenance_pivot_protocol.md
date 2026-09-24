# Maintenance pivot: analysis protocol, 24 September 2026

Written before fitting models or inspecting their performance. User requested an
empirical feasibility test, including negative results, not a hypothetical story.

## Decision and outcome

Decision: which existing Parks inspection sites warrant supplementary maintenance
checks? This does not replace the independent random PIP audit or prescribe repairs.
Unit: inspection property (`prop_id`) at a January/July planning date. Multiple
comfort stations at a site/visit are aggregated: any U = unacceptable; all A =
acceptable; otherwise unknown. Do not assume ordinal `csnumber` is a permanent ID.
Target: outcome at the first regular PIP visit in the next half-year. Unknown ratings
and sites without follow-up are reported separately, never converted to passes.
This validates ranking within the observed/rated cohort, not all eligible sites.

## Information and split

- Features only from inspections before the planning date AND entered before it.
- Require a previous visit within two years. Use up to three years of prior history.
- Model rows: 2018 onward. History may use earlier records.
- Development: 2018–2023; validation: 2024; final evaluation: 2025 and first half 2026.
- Select model/hyperparameters and strongest simple benchmark on 2024 performance,
  then freeze choices and refit through 2024. Do not tune on 2025–2026 results.
- Regular PIP inspections only, not SWEEP or other selected inspection types.
- No same-visit condition subscore, target-date visitor count, current closure flag,
  current asset condition, or current inventory status as historical predictor.

## Models, benchmarks, metrics

Benchmarks: random selection, last rated outcome, last-three rated failure rate,
three-year smoothed historical failure rate, and last-fail then recent-history rule.
Models: logistic (basic/history), shallow classification trees (max depth 3,
minsplit 60, minbucket 25; CP .005/.01/.02/.04). No exhaustive search.
Choose by mean precision at top 20% of rated sites within each validation half-year;
break close ties by lower Brier score. Also report top 50, 10%/30% budgets, recall,
ROC AUC, Brier score and calibration. Fractional allocation at tied cutoffs prevents
a lucky alphabetical order from deciding a baseline's score. Test benchmarks under
the same capacity. Confidence intervals use paired parent-park cluster bootstrap.

Secondary checks: each test period separately; condition on last rated pass to
distinguish new failures from persistent problems; unknown/follow-up rates; boroughs;
leave high-volume parent parks out if concentration threatens the result.

## Claims allowed

Success means useful held-out prioritisation, with uncertainty and comparison to the
best simple rule. Do not equate prediction with failures prevented or repair ROI.
If a simple rule is as good, recommend the rule. If history is uninformative, say so.
Complaint features may be tested as a separately labelled extension with earlier
complaints only. Spatial access is a present-day context overlay, not retrospectively
known supply or a causal effect. No public site/deck changes in this task.
