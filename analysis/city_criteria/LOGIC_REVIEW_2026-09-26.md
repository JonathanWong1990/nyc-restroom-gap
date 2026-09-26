# Logic and methodology review — 26 September 2026

## Verdict

**Provisional assessment: B+ (roughly 83–87/100) as an MBA analytics project.** This is an independent reviewer's judgment, not a prediction of the professor's grade. The model has a strong policy question, a coherent progression from demand to available supply to possible interventions, and useful sensitivity analysis. Keep the current direction and refine the claims; a wholesale model change is not warranted on logic alone.

**Presentation readiness:** Close, with three material interpretation issues to resolve first. They affect what the results can support, but do not invalidate the project's overall structure.

This review assumes the reported numbers are correct. It considers the current published Walkthrough and Limits tabs, `CHECKING.md`, `README.md`, `REVIEW_RESPONSE.md`, the current R scripts, and the course's *Guidelines for the Final Presentation*. It is **not** the requested follow-on audit of calculations, script execution, data quality, or external-source accuracy. The deck-outline tab is intentionally frozen and was not assessed.

## What works

- The project answers a specific, relevant question: where is evening restroom access missing, and when could an existing facility address it?
- The revised two-stage approach evaluates repairs and longer hours at existing facilities' own coordinates, then places new units for the remaining candidate-site gap. This resolves the main conceptual defect in the earlier one-stage version.
- Demand, supply, the candidate-site gap, and resident coverage are distinguished. The project also distinguishes better access from progress toward the law's restroom count.
- Scenario tests expose consequential assumptions, especially park opening hours, the high-demand cutoff, the service radius, and whether private toilets are genuinely public.
- The Limits tab acknowledges small-sample pilot weights, in-sample AUC, approximate walking distance, facility capacity, hours uncertainty, and site feasibility.

## Three material issues before presentation

### 1. The resident result does not establish an “at least 830” minimum

The resident-coverage procedure in `R/09_resident_coverage.R` selects new units greedily at residential grid points, after using eligible existing facilities. It reports 830 new units for full modelled resident coverage. A greedy feasible solution does **not** prove that no smaller solution exists. The model's flexible siting and omission of workers, visitors, and capacity could make a real implementation require more; those considerations do not turn the computed 830 into a mathematical lower bound.

**Action:** Replace “at least 830,” “830 is a floor,” and similar wording in the headline, Walkthrough, and Limits with “830 in this illustrative resident-coverage scenario,” or an equally clear conditional statement. Keep the 80%, 90%, and 95% milestones, which convey the useful diminishing-returns result. A formal minimum would require an optimisation proof under explicitly defined assumptions.

### 2. The 24-unit plan has not been combined with the resident plan

`R/05_gap.R` chooses 24 new units to finish covering high-demand candidate sites. `R/09_resident_coverage.R` separately chooses units for resident coverage at any residential grid point. The published recommendation says to build the 24 first and then expand by residents reached, but the displayed resident counts have not been recomputed with those 24 locations fixed in place. The 24 and 830 figures therefore describe different optimisation exercises, not one tested deployment sequence.

**Action:** Either present them explicitly as complementary analyses, or rerun the resident-coverage exercise with the 24 proposed units already in place and report the combined sequence. Do not add or compare the two counts as though they are directly interchangeable.

### 3. Existing-facility coverage is conditional on operational feasibility

The two-stage model shows which existing facilities could cover mapped gap points if repaired or kept open until 10pm. It does not establish that all 103 selected park extensions, 35 other-operator extensions, or 16 repairs are operationally feasible or cost-effective. Longer hours at libraries and other operators may require access arrangements, staffing, security, and funding. The stated 95% candidate-gap coverage is conditional on completing the selected actions.

**Action:** Describe the 154 facilities as a prioritised list to verify and negotiate. In the recommendation, make actual hours, operator consent, physical access, repair scope, and costs explicit decision gates before claiming deliverable coverage.

## Smaller refinements

- The 17 pilots reveal associations with the City's early site selections, not an independent measure of public need or the City's actual decision weights. The page mostly handles this well; avoid phrases such as “answer key” or “give those factors weights” when they imply ground truth.
- The top-third citywide demand ranking is heavily concentrated in Manhattan. If equity across boroughs is a policy objective, make it an explicit scenario or constraint rather than expecting the fitted 5% poverty term to deliver it.
- The greedy procedure is a heuristic that finds a workable cover. “Solves the maximal covering location model” overstates what it proves, particularly since the exercise covers all selected gap points rather than maximising coverage under a fixed facility budget.
- The 1,247 gap *sites* are candidate grid points, not people. Keep that unit visible when discussing what share of the gap is covered; the resident analysis answers a different question.
- The course allows 12 minutes plus 3 minutes of Q&A. Condense the 14-step published walkthrough for oral delivery into four messages: evening-access problem, modelled gap, potential existing-facility response, and the separate building/count decision. Retain detailed methods and limits as backup material.

## Grade signal

The current method and story are **good enough to retain**. The three issues above are substantive claim and decision-logic fixes, not a reason to rebuild the analysis. If those claims are corrected and the follow-on numerical audit passes, the project has A-range potential. If the “at least 830” claim and the untested combined deployment sequence remain in the final presentation, I would keep the provisional assessment at B+ rather than call the work presentation-ready.

## Next review round

Audit the revised calculations and scripts separately: reproduce the headline numbers; inspect the supply/status rules and two-stage coverage; test whether the 24 high-demand units alter the resident curve; and classify discrepancies as major, moderate, or minor. This logic review deliberately did not perform those checks.
