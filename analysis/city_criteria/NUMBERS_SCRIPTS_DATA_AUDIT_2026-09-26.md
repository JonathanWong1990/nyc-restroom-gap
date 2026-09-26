# Numbers, scripts and data audit — 26 September 2026

## Decision signal

**Keep the model, but correct the supply/action rules and published claims before presenting it as an implementation plan.** The current headline outputs reproduce exactly from the local scripts and inputs. The central result—that evening access is scarce and existing facilities could address much of it—survives the checks below. Two inconsistencies materially affect the daytime baseline and what a “repair” accomplishes at 9pm.

My provisional assessment of the **currently published** analysis is **B** for an MBA presentation, with B+/A-range potential after the corrections and a clear account of operational feasibility. This is a review signal, not a forecast of the professor's grade. It does not call for a wholesale rebuild.

## Scope and verification method

I reviewed the current scripts `R/01_features.R`, `05_gap.R`, `06_gap_figures.R`, `07_private_supply.R`, `08_citywide.R`, `09_resident_coverage.R`, `10_extra_figures.R`, the upstream `Build_Plan/prototype/R/01_prep.R`, the saved NYC and Census inputs, `cache/prep.rds`, the published Walkthrough and Limits tabs, the cached City pilot release, and the cached text of Local Law 58. Per `CHECKING.md`, I excluded the superseded “next 50” scripts and frozen deck outline.

I reran `01`, `05`, `07`, `08`, and `09` in an **isolated `/private/tmp/nyc-restroom-audit/` copy** with only the output directory changed. The project's scripts, caches and outputs were not overwritten. The new feature object and every field of the new gap object match the saved objects. The rerun CSVs for pilot model, selected facilities, new units, gap sensitivity, private-supply scenarios, citywide coverage and resident coverage match the saved CSVs. I also ran independent spatial checks and bounded alternative scenarios. All alternative results below are audit tests, not revised official results.

### Headline results reproduced

| Result | Saved and rerun |
|---|---:|
| Register records / marked operational | 1,066 / 975 |
| Candidate sites / pilot sites / model controls | 5,814 / 17 / 5,756 |
| Base 9pm gap | 1,247 candidate points |
| Existing facilities selected | 154: 103 park hours, 35 other hours, 16 repair/reopen |
| Gap points covered by selected existing facilities | 1,183 of 1,247 |
| New candidate-site units selected | 24; every remaining gap point covered in the model |
| Park-hours alternative as coded | 355 gap points, 29 existing interventions, 24 new units |
| Resident coverage as coded | 72.4% at 2pm; 4.4% at 9pm; 73.4% after 761 existing interventions |
| Further units for resident thresholds as coded | 38 to 80%; 171 to 90%; 296 to 95%; 830 to 100% |
| Complaint hotspot overlap | 29 areas; 3 pilots, 24 selected existing facilities, 2 new units inside |

The Local Law 58 source supports the 2,120 target and at-least-half-publicly-owned requirement. The saved register supports 975 marked operational records, making the arithmetic difference 1,145. The January–June 2026 Parks inspection input yields 139 unacceptable results among 693 rated inspections, or 20.06%, consistent with the displayed 20.1%. The cached City release supports 17 announced pilot locations, a $4 million one-year pilot, and intended 7am–10pm hours. These checks establish source-to-output consistency, not live status of every restroom.

## Findings ranked by impact

### High — “Repair or reopen” does not itself supply a restroom at 9pm

**Where:** `R/05_gap.R` lines 83–104 and 123–126; `R/09_resident_coverage.R` lines 16–35.

Every one of the 16 existing facilities labelled **Repair or reopen** in the high-demand plan is a Parks restroom with modelled hours of **8am–4pm**. The code selects it as eligible at 9pm and marks it covered immediately. The resident analysis similarly uses 97 repair/reopen selections at 9pm; all facilities in the broken pool have the same 8am–4pm placeholder hours. Thus the model is implicitly asking for **repair/reopening plus an extension to 10pm** at those facilities, while the map, action table and recommendation name only repair/reopening.

This is material, not a label-only nit: if the 16 selected facilities are repaired but keep their 4pm hours, and the other 138 existing actions and 24 new units remain as selected, **77 original gap points remain without modelled 9pm coverage**. If repairs are removed and the candidate-site plan is reoptimised, it finds **152 hour extensions plus 29 new units**, rather than 154 existing interventions plus 24 new units. That is an alternative scenario, not the recommended solution.

For residents, reoptimising with **hour extensions but no repairs** reaches **69.0%** after existing interventions, versus **73.4%** as coded. It needs **69** further units to reach 80% and **876** for complete modelled resident coverage, versus 38 and 830 in the published scenario. This alternative holds the other assumptions fixed.

**Correction:** Make the repair action explicitly “repair/reopen **and** keep open to 10pm,” validate that both actions are feasible, and account for both costs. Alternatively, change eligibility so a repair with 4pm hours cannot cover a 9pm point, then rerun the plan and figures. Do not present the current 16 or 97 as repair-only actions that close an evening gap.

### High — The daytime supply rule conflicts with the project’s own broken-restroom rule

**Where:** `R/01_features.R` lines 48–53; `R/05_gap.R` lines 67–75; `R/09_resident_coverage.R` lines 16–29; figures in `R/06_gap_figures.R` lines 61–89.

The `open_at()` function uses register status and posted hours but does **not** exclude `removed_closed` or `removed_fail`. At 2pm, **81 facilities** that the upstream preparation flagged as closed long-term (34) or repeatedly failing inspection (47) are counted among the **954 open** restrooms. The published text also says these 122 flagged facilities, including 41 additions not operational in the register, do not reliably serve anyone.

There are two defensible definitions, but the site must use and label one consistently:

| 2pm supply definition | Facilities counted open | Residents within 500 m |
|---|---:|---:|
| As coded: register operational + posted hours | 954 | 72.4% |
| Exclude the 34 facilities matched as long-term closed | 920 | 70.8% |
| Also exclude 47 repeatedly failing facilities | 873 | 69.0% |

The last row treats repeated failure as unusability, which is the **project's assumption**, not direct observation that each facility was closed every day. With that definition, candidate-site 2pm coverage is **70.2% rather than 71.4%**, and the original gap's all-day/evening-only split changes from **65/1,182 to 84/1,163** under the saved demand score. Refitting the pilot model and rerunning the base gap under the strict definition gives **1,246 gap points, 155 existing facilities, and 24 new units**—a small change to the main intervention conclusion.

The park-hours scenario is more affected: when placeholder Parks hours are extended to 10pm, the existing `open_at()` rule also treats the 81 flagged facilities as available at 9pm. With the strict definition and a model refit, the scenario becomes **396 gap points and 37 existing interventions**, versus the published **355 and 29**; the new-unit count stays 24. Excluding only the 34 long-term-closed facilities raises the gap to 363 under the saved demand score. These are conditional sensitivity values, not verified actual opening hours.

**Correction:** Decide whether repeatedly failing facilities count as unavailable. Exclude genuinely closed facilities in supply calculations; apply the chosen quality rule consistently in features, coverage, figures and scenarios; rerun the affected outputs. If the original 954 is retained as a register-based statistic, label it **“listed as operational and scheduled open”**, not “actually open and working.”

### Moderate — Planned pilot sites are treated as already operating

**Where:** `R/05_gap.R` lines 73 and 94–104; cached `Restroom_Rebuild/data_raw/nycgov_mayor_pilot_release_20260923.html`.

The City release says installation of the 17 pilot units **had begun** on 16 September 2026; it does not verify that all 17 were operating on the date used for this analysis. The gap calculation nevertheless excludes every candidate point within 500 m of any of the 17 as already served. If none is counted as operating, while all other assumptions are held fixed, the model has **1,358 gap points, 161 existing interventions and 25 new units** rather than 1,247, 154 and 24. The pilot assumption therefore removes **111** potential gap points, though it changes the selected new-unit count by only one in this bounding scenario.

**Correction:** Verify commissioning/open status site by site, or label the current gap as **“assuming all 17 announced pilot units are operating 7am–10pm.”** Keep the 975 register count and pilot inclusion on a consistent date basis when discussing progress toward the legal target.

### Moderate — The 24-unit recommendation and resident curve are separate plans

**Where:** `R/05_gap.R` and `R/09_resident_coverage.R`; published recommendation.

The 24 units are chosen to cover high-demand candidate points. The resident curve independently places units at residential grid points after its own existing-facility stage. As a bounded combination check, keeping the 761 resident-stage existing interventions, placing the 24 candidate-site units, and then adding resident-optimised units raises resident coverage to **75.1%** before further additions. It needs **813 additional units** for complete modelled resident coverage: **837 total new units including the fixed 24**, compared with 830 when resident units are optimised from scratch. This is a scenario comparison; a fully joint reoptimisation could give a different count.

**Correction:** Keep the two plans separate in the published wording or run a joint sequential plan before calling “24 first, then build toward 830” a tested sequence. The earlier logic review also applies: 830 is a greedy scenario result, **not a proven minimum or floor**.

## Data and reproducibility notes

- The pilot release publishes **place names**, not exact installation coordinates. The upstream geocoding script uses park/plaza representative points and street intersections; one named site spans two Parks properties. Distances and the pilot model should be interpreted with that location uncertainty in mind.
- The 150 m residential grid spreads each census tract's population evenly across retained points. The 100% coverage end of the curve is consequently sensitive to the grid and to small, isolated population allocations; it should be presented as a modelled scenario, not a precise construction requirement.
- The private-supply runs reproduce their saved output. The raw chain file has 1,886 rows; the script drops 28 without coordinates and four false chain matches to use 1,854. Hours, toilets and non-customer access are unobserved, so those scenarios are bounds and hypotheses, as the site already says.
- `CHECKING.md` says `prep.rds` is not on GitHub. A reviewer starting from the public `analysis/city_criteria/` folder cannot rerun `01_features.R` or the subsequent models without rebuilding that input from the upstream preparation script and raw sources. Provide a reproducible build path or a permitted copy of the cache.
- Source timing varies: the restroom register is from June 2025, while the pilot announcement and several other inputs are from September 2026. Refreshing hours, status and pilot commissioning is a prerequisite for any real deployment recommendation.

## Recommended order of work

1. Decide and document the supply-status rule; fix the functions and regenerate all dependent numbers and figures.
2. Require both repair/reopening **and** evening-hours extension for broken facilities used to cover 9pm demand, or reoptimise without those facilities.
3. Verify pilot operating status or state the all-pilots-open assumption next to the 1,247 figure.
4. Correct the “830 minimum/floor” language and keep the 24-site and resident plans separate until a combined optimisation is run.
5. Recheck the published Walkthrough, Limits, figures and `CHECKING.md` against the revised outputs, then rehearse the 12-minute presentation.
