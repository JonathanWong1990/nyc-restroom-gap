# Maintenance-pivot replication: independent rebuild and stress tests

24 Sep 2026 (overnight). Independent rebuild of the maintenance-pivot backtest that ChatGPT/Codex produced. I wrote the panel and evaluation from the raw cached files in `Restroom_Rebuild/data_raw/`. I did not look at `Maintenance_Pivot_Feasibility/R/` until my own numbers were done. I read their code only afterwards, to explain the differences (R3 onwards).

## Verdict: REPLICATES, but the logistic's "88" is fragile

- **The headline numbers reproduce exactly.** Once three small definitions are matched, I get 48.9 / 79.1 / 86.1 / 88.0 known failures in 411 slots. The cohort also matches: 1,685 rated test outcomes, 244 U, 324 unrated, 41 with no visit, 644 properties and 516 parent parks. My fully independent first pass, before I read their code, got 48.9 / 79.5 / 86.1 / 80–84.5. The rules matched straight away. Only the logistic moved.
- **No leakage found.** The time split is clean.
- **"History beats random" is robust.** It holds at 10%, 20% and 30% capacity, in all three test periods, and with other outcome definitions. The bootstrap interval for smoothed history minus random is +22 to +50 failures.
- **"The model beats the rule" is not robust.** Nine reasonable logistic specifications capture between 75 and 88 failures. 88 is the top of that range. One variant scored higher on their own 2024 selection metric than the model they chose, and it gets only 79 on the test. The honest reading is that the logistic roughly equals the 3-year history rule. ChatGPT's findings say this too, but the ordered 49 / 79 / 86 / 88 bar chart suggests more.
- **All of the gain comes from sites that already failed recently.** Every failure captured above random, by every method, is at a site with at least one U in the prior 3 years. 88 of the 244 test failures (36%) happen at sites with a clean 3-year record. History cannot flag those, and on that subgroup every history method is no better than random.
- **"Failed last time" is not the "simple rule" that gets most of the benefit.** It captures 65.6 failures, which is only about 43% of the logistic's gain over random. The 3-year failure-share rule captures about 95% of that gain.

## Numbers: mine vs ChatGPT's

Test set: 2025 H1, 2025 H2 and 2026 H1. All eligible site-periods (2,050), with 20% capacity per period (ceiling of 20% of 685/683/682, which is 137 each, 411 slots in total). Known failures captured use fractional allocation at tied cutoffs.

| Method | ChatGPT | Mine, independent first pass (R2) | Mine, definitions matched (R3/R5) |
|---|---:|---:|---:|
| Random, expected | 48.9 | 48.93 | 48.93 |
| Last-three failure share | 79.1 | 79.45 | **79.06** |
| Smoothed 3-yr history `(u+0.5)/(n+5)` | 86.1 | **86.06** | 86.06 |
| Logistic, their spec | 88 | 84.5 (linear days) | **88.0** |
| Logistic, my own spec | — | 80.0 | — |
| "Failed last time" (last rated = U), random fill | not headlined | 65.6 | 65.6 |

| Cohort | ChatGPT | Mine |
|---|---:|---:|
| Train 2018–23 rated / U | 6,579 / 777 | 6,579 / 777 |
| Select 2024 rated / U | 1,170 / 130 | 1,170 / 130 |
| Test rated / U | 1,685 / 244 | 1,685 / 244 |
| Test unrated first visit / no visit | 324 / 41 | 324 / 41 |
| Test props / parent parks | 644 / 516 | 644 / 516 |

Per period at 20% (definitions matched):

| Period | Random | Last-U | Last-3 | 3-yr | Logistic |
|---|---:|---:|---:|---:|---:|
| 2025 H1 | 14.0 | 16.5 | 18.3 | 21.2 | 20 |
| 2025 H2 | 13.6 | 20.3 | 25.6 | 27.4 | 28 |
| 2026 H1 | 21.3 | 28.8 | 35.1 | 37.5 | 40 |

These match their `all_eligible_selection_metrics.csv` per-period values exactly.

### Differences explained (after reading their M1)

1. **Last-three, 79.45 vs 79.06.** They take the last three rated visits *inside the 3-year window*. I first took the last three rated visits from all history. With the window matched I get 79.06.
2. **Logistic, 84.5 vs 88.** Their formula is `y ~ last_fail + recent_rate + log1p(days_since) + borough + half`. I had guessed a linear `days_since` from the findings text. Using `log1p` gives 88.0. Where borough comes from (the `prop_id` prefix or the sites table) makes no difference: the two agree on all rows.
3. **Unit, eligibility, entry-date filter, outcome, tie handling and capacity rounding** all matched first time, with no reference to their code.
4. **Something not stated in the findings:** they chose the model on **rated-only** 2024 precision, then headlined it on the **all-eligible** universe. That is defensible, but the selection margin was thin: `logistic_basic` 0.1913 vs `last_three` 0.1796 vs `logistic_history` 0.1775.

## Stress tests

### 1. Leakage: none found

- History uses `inspection date < P` and `entry date < P`. Outcomes use `date >= P`. There are 0 rows with last history visit on or after P, and 0 with outcome before P.
- Visits dated before P but entered on or after P: **0 in every one of the 17 planning dates**. Entry lag since 2015 is at most 6 days. So the entry filter never binds, and nothing leaks through late entry.
- Same-day visits: 29 visits fall exactly on a planning date (all on 1 July). They are outcomes, not features.
- Training labels: 0 visits from 2024 were entered in 2025, and 0 from 2023 were entered in 2024. The refit through 2024 therefore uses nothing unavailable on 1 Jan 2025. The model stays frozen for 2025 H2 and 2026 H1, which is conservative.
- `[UNVERIFIED]` The raw files are a Sept-2026 snapshot. If Parks revised ratings after the fact, or dropped sites, the "as known then" history could differ from what was actually on file. The data has no revision history, so this cannot be checked.

### 2. Is first-visit timing correlated with risk? No

- Spearman correlation between the 3-year risk score and days from planning date to first visit: **−0.04**. Median days to visit does not trend across risk quintiles (95 / 54 / 82 / 55 / 71).
- Failure rate by month-within-half of the first visit: 14.1%, 17.8%, 12.1%, 14.3%, 13.9%, 19.4%. There is no early-visit risk pattern.
- Changing the outcome definition does not overturn the history effect:

| Outcome | Random | Last-3 | 3-yr | Logistic |
|---|---:|---:|---:|---:|
| Any U in the half-year | 59.2 | 91.9 | 94.1 | 99.5 |
| Last rated visit in the half is U | 51.1 | 78.0 | 77.3 | 85.5 |

  These rows use R2's slightly different logistic and last-3 definitions.
- **Caveat:** missing outcomes cluster in the high-risk groups. The unrated-first-visit share is 3% in the lowest risk quintile and 22–28% in the upper-middle and top quintiles. So priority lists contain more unknown slots (logistic 99, 3-yr 102.6, random 73). Known-failure yield could understate the lists' true yield, or overstate it if unrated means "fine". The quintiles are uneven because of tied scores.

### 3. Capacity: holds at 10% and 30%

| Capacity (slots) | Random | Last-U | Last-3 | 3-yr | Logistic |
|---|---:|---:|---:|---:|---:|
| 10% (207) | 24.6 | 38.2 | 45.4 | 42.7 | 46 |
| 20% (411) | 48.9 | 65.6 | 79.1 | 86.1 | 88 |
| 30% (616) | 73.3 | 87.9 | 110.7 | 112.0 | 112 |

History beats random by about 1.5–1.9x at every capacity. Which rule ranks first among last-3, 3-yr and logistic changes with capacity: last-3 is ahead of 3-yr at 10%, and all three tie at 30%.

Parent-park cluster bootstrap (1,000 draws, R4), as known failures out of 411 slots (percentage points in brackets):

| Comparison | 95% interval |
|---|---|
| Logistic − 3-yr | −10.6 to +13.7 (−2.6 to +3.3 pp) |
| Logistic − last-3 | +0.6 to +15.3 (+0.1 to +3.7 pp) |
| 3-yr − random | +22.4 to +49.9 |
| Logistic − random | +23.5 to +53.1 |
| Last-U − random | +5.6 to +28.0 |

The first two match ChatGPT's −2.3/+3.3 and +0.1/+3.8.

**Specification fragility of the logistic** (R3). All variants are trained through 2024, test at 20%:

| Specification | 2024 selection precision (rated) | Test known failures |
|---|---:|---:|
| Their exact spec | 0.191 | **88.0** |
| Linear days | 0.191 | 86.0 |
| Last-3 over all history | 0.185 | 88.2 |
| **No borough** | **0.196** | **79.0** |
| + smooth3 | 0.178 | 81.5 |
| smooth3 only | 0.161 | 86.1 |
| u3 + n3 + last-U + days | 0.156 | 75.0 |
| My own R2 spec | 0.178 | 80.0 |

Dropping borough scores *higher* on their 2024 selection metric and scores 9 fewer failures on the test. The 88 is a favourable draw from roughly 75 to 88. Nothing supports "logistic > 3-yr rule". To be fair to ChatGPT, their text does not claim that; the bar chart implies it.

### 4. Chronic sites: the yield is recurring known-bad sites

- The 244 test failures come from 196 distinct properties. 43 properties fail in 2 or more of the 3 test periods, and they account for 91 of the 244 failures.
- 156 of 244 failures (64%) are at sites with at least one U in the prior 3 years. Those sites make up 901 of the 2,050 site-periods.
- Of the failures each method captures, the share at sites with a prior-3-year U is **100%** for last-3, 3-yr and logistic. For last-U it is 59.0 of 65.6, and the other 6.6 come from the random fill.
- The rated failure rate rises with the number of prior-3-year U's: 0 → 9.4%, 1 → 17.7%, 2 → 26.0%, 3 or more → 29.8%.
- **Sites whose last rating was A** (1,775 site-periods, 193 failures; 20% within that group): random 38.7, last-3 62.2, 3-yr 63.4, logistic 58–65. History still helps here, but only because of *older* U's in the 3-year window.
- **Sites with last rating A and no U in the prior 3 years** (1,149 site-periods, 88 failures): random 17.7, last-3 18.9, 3-yr 12.4, logistic 13–15. **No history method beats random** at spotting first-time failures. More than a third of failures are invisible to this approach.

### 5. The "sites that failed last time" rule

- The rule flags about 91 sites per period (13% of eligible), 275 slots in total.
- Of those 275, 51 were known failures: 18.5% per slot, and 25.4% precision among rated outcomes, against a 14.5% base rate.
- Filled to 20% at random, it captures **65.6**. That is about 43% of the logistic's gain over random.
- "Any U in the prior 3 years" flags 901 site-periods. Filled to 20%, it captures 71.1.
- The simple rule that gets about 95% of the benefit is the **3-year failure share**: rank sites by the share of their inspections over the past 3 years that were unacceptable. "Failed last time" does not get there.

## Other caveats worth carrying forward

- The 2026 H1 base rate jumps to 106 failures, against 68–70 in each 2025 half. That period supplies the biggest absolute gains.
- 2025 H1 is the weakest period: 3-yr 21.2 and logistic 20, against random 14.
- Known-failure yield is a detection count, not failures prevented.
- The 411 slots are 3 × 137 repeated planning opportunities, not 411 distinct toilets.

## The one sentence a presenter may say

> "In a held-out test on 2025 to mid-2026, sending one in five extra checks to the sites with the worst three-year inspection record would have found about 86 recorded failures instead of about 49 at random, and a logistic model did no better than that simple rule, though about a third of failures happened at sites with a clean three-year record that no history-based list could have flagged."

Do not say "the model finds 88 vs 86". Do not say "a simple 'failed last time' rule gets most of the benefit": that rule gets 65.6.

## Files (all in `Overnight_2026-09-24/2_pivot_replication/`)

- `R1_build_panel.R`: independent panel build, producing `panel.rds` and `visits.rds`.
- `R2_evaluate.R` and `R2_output.txt`: independent headline, capacities, bootstrap, and stress tests 1, 2, 4 and 5. Its "their" logistic uses linear days. Its distinct-props count in ST4 counts any fractional tie weight and is superseded by R3.
- `R3_differences_and_fragility.R` and `R3_output.txt`: written after reading their code. Exact-match definitions, the specification-fragility table, and the weighted chronic-site accounting.
- `R4_bootstrap_exact.R` and `R4_output.txt`: parent-park cluster bootstrap on the exact spec.
- `R5_capacity_exact.R` and `R5_output.txt`: 10/20/30% by period, definitions matched.
- `R6_misc.R` and `R6_misc_output.txt`: training-label entry-lag check and the any-U-in-3-years rule.

No data was downloaded. Nothing was written outside this folder.
