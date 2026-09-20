# Methods from outside urban-restroom analysis — notes (2026-09-20)

Researched to unstick two measurement problems: (A) sparse/biased 311 signal as a
demand proxy; (B) no measurable ROI/benefit for restroom investment. Full citations
below; briefing summary delivered separately to the calling agent.

---

## Problem A — sparse signal (~3,600 events / 197 areas / 6.7 yrs)

### A1. Capture-recapture / multiple systems estimation (MSE)
- What it is: epidemiology/demography technique to estimate the TRUE size of a hidden
  population from two or more independent, imperfect "capture" lists, using the
  overlap between lists. If list A and list B each miss different people, the overlap
  tells you the undercount. Standard estimator: Lincoln-Petersen (N ≈ n1·n2/m, m =
  overlap); modern MSE work uses log-linear models for 2+ lists.
- Concretely here: 311 public-urination complaints are one "list." A genuinely
  independent second list would be needed — e.g. NYPD summonses/violations for public
  urination (if geocoded and obtainable), or DSNY street-cleanliness inspection scores,
  or a citizen-science/sensor pilot. The two lists must be independent in *why* an
  event gets captured (311 = someone annoyed enough to complain online; a summons =
  an officer physically present) — that's plausible enough to try.
- Requirement: address- or block-level records from a second source, for the same
  window, that can be matched geographically to 311 records. This is the hard part —
  NYPD summons data for public urination specifically may not be published at this
  granularity. **Flag: existence of a usable second list is unverified — this is the
  single biggest feasibility risk of the whole idea.**
- Difficulty: moderate-to-high. Needs the second dataset; log-linear MSE in R is
  straightforward (package `Rcapture` implements it) once data exists.
- Citation: Chan, L. et al., "Multiple Systems Estimation (or Capture-Recapture
  Estimation) to Inform Public Policy," *Annual Review of Statistics and Its
  Application*, 2018. https://www.annualreviews.org/content/journals/10.1146/annurev-statistics-031017-100641
  (accessed 2026-09-20). Also PubMed abstract:
  https://pubmed.ncbi.nlm.nih.gov/30046636/ (accessed 2026-09-20).

### A2. "Dark figure of crime" / victimisation-survey correction
- Criminology's parallel problem: recorded crime undercounts true crime because
  reporting is selective. Corrected via victimisation surveys (e.g. US National Crime
  Victimization Survey) that ask a representative sample "did this happen to you,
  did you report it" and use the reporting *rate* to scale up official counts.
- Concretely here: without budget for a citywide survey, the *idea* is still useful —
  it reframes 311 counts explicitly as "reported incidents," not "incidents," and
  argues for a plausible, cited reporting-rate multiplier (even a sensitivity range,
  e.g. 1 in 5 to 1 in 20 events reported) rather than treating raw counts as truth.
  A recent methods paper explicitly builds a correction from reporting-rate variation;
  the same logic could be adapted with an assumed/benchmarked reporting rate rather
  than a bespoke survey.
- Citation: Wheeler, A.P. & Piquero, A.R., "Using Victimization Reporting Rates to
  Estimate the Dark Figure of Crime: A Case Study of Domestic Violence," *Journal of
  Quantitative Criminology / Sage*, 2025.
  https://journals.sagepub.com/doi/10.1177/00111287251359210 (accessed 2026-09-20;
  abstract only, did not access full text — treat methodology detail as unverified).
  General concept: https://en.wikipedia.org/wiki/Dark_figure_of_crime (accessed
  2026-09-20, tier: reference/background only).
- Difficulty: low to state as a caveat/sensitivity range; high to do rigorously (needs
  a real survey or a defensible borrowed reporting-rate estimate — none found for
  public urination specifically).

### A3. Small-area estimation: shrinkage and spatial smoothing
- The statistics-of-rare-counts literature (used for disease mapping, small-area
  crime rates) is built exactly for "~15 events per area, 197 areas." Two standard
  moves:
  1. **Empirical-Bayes / James-Stein shrinkage**: pull each area's raw rate toward the
     citywide (or borough) average, weighted by how little data that area has — an
     area with 3 events gets pulled hard toward the mean; an area with 40 stays close
     to its raw rate. This alone fixes the "one repeat complainant distorts the
     ranking" problem, because it discounts high-variance small counts.
  2. **Spatial smoothing (BYM / CAR models)**: additionally borrow strength from
     *geographic neighbours*, not just the citywide mean — appropriate because need is
     plausibly spatially correlated block-to-block.
- Implementability in R: **yes, without exotic tooling.** Poisson-gamma empirical
  Bayes shrinkage is a few lines of base R (or package `ebbr`). Full BYM/CAR spatial
  models are one function call in `CARBayes` (`S.CARbym()`), which needs only a
  standard binary neighbourhood adjacency matrix built from a shapefile — well within
  scope for a course project team already handling NTA geography. `INLA` is the other
  common route but has a steeper install; CARBayes is simpler and CRAN-standard.
- Recommendation: at minimum do (1) — it directly answers "a few repeat-complainant
  addresses are distorting the ranking" — and consider (2) as a stretch/sensitivity
  check, not the headline model.
- Citations: Lee, D., "CARBayes: An R Package for Bayesian Spatial Modeling with
  Conditional Autoregressive Priors," *Journal of Statistical Software*, 2013.
  https://www.jstatsoft.org/article/view/v055i13 (accessed 2026-09-20). Background on
  shrinkage for small-area rare-event rates: "Small Area Shrinkage Estimation,"
  *Statistical Science*, 2012, https://projecteuclid.org/journals/statistical-science/volume-27/issue-1/Small-Area-Shrinkage-Estimation/10.1214/11-STS374.full
  (accessed 2026-09-20, abstract reviewed, not full text).

---

## Problem B — no measurable ROI

### B1. Break-even / threshold / "switching value" analysis — THE recommended fix
- What it is: instead of estimating the dollar benefit (which the team cannot do),
  invert the question: **given the known cost, how large would the benefit have to be,
  per year, to justify the spend at a standard discount rate?** Then ask whether that
  required benefit is *plausible* given even rough, defensible proxies (e.g. cost per
  additional 311 complaint avoided, cost per marginal visit, comparison to a known
  benchmark like the SF result below). This produces a decision-usable number without
  ever claiming to have measured the actual benefit.
- Authority for this being a legitimate, standard public-sector technique (not an
  improvisation): **UK HM Treasury Green Book** (the UK government's official
  appraisal guidance, tier 1 — government methodology standard) explicitly instructs
  analysts to calculate "switching values" via sensitivity analysis, and separately
  states that for interventions such as **crime reduction** — a close analogue to a
  public-nuisance/street-fouling intervention — **break-even analysis may be the
  appropriate approach instead of demonstrating a high benefit-cost ratio**, precisely
  because the benefit side resists reliable quantification.
  Citation: HM Treasury, *The Green Book: Central Government Guidance on Appraisal and
  Evaluation*, 2026 edition, https://assets.publishing.service.gov.uk/media/698dbcd17da91680ad7f4308/The_Green_Book_2026.pdf
  (accessed 2026-09-20; searched via secondary summary, recommend the team open the PDF
  directly and pull the exact switching-value section/page before citing in the deck —
  **flag: I did not open and read the primary PDF text directly, only a search-engine
  summary of it; verify before quoting a page number**).
- Textbook grounding: Boardman, Greenberg, Vining & Weimer, *Cost-Benefit Analysis:
  Concepts and Practice* (Cambridge, multiple editions) — the standard graduate CBA
  textbook — covers sensitivity analysis and switching/break-even values as core
  method for public projects with uncertain benefits.
  https://www.cambridge.org/highereducation/books/cost-benefit-analysis/484720E57798B7E7A29C7156407CD4A1
  (accessed 2026-09-20, publisher page only — did not access full chapter text).
- **Worked template for the deck:**
  1. Take CapEx + annualized O&M for the shortlisted intervention (already have this
     from the Parks Capital Tracker `4hcv-tc5r` cost data).
  2. Pick a discount rate (standard municipal ~3-7%) and time horizon (e.g. 10-20 yr
     facility life) → compute required annualized benefit to reach NPV = 0.
  3. Convert that dollar figure into a plausible per-unit benefit (e.g. "this requires
     avoiding X public-urination incidents per year at $Y/incident using an established
     nuisance-cost proxy, OR Z avoided medical/cleanup cost events, OR $/added visit").
  4. State it as: "for this project to break even, each dollar of it needs to prevent
     [X]. Is that plausible given [comparable evidence]?" — then bring in B2/B6 below as
     the plausibility check.
  This is exactly the honest, defensible move the team needs: it does NOT invent a
  benefit number, it inverts the question and lets the reader judge plausibility —
  matching the course's own emphasis on managerial interpretation over spurious
  precision.
- Difficulty: low. This is arithmetic on numbers the team already has (CapEx from the
  cost dataset) plus a chosen discount rate — no new data collection required. This is
  the single most implementable and highest-leverage idea in this brief.

### B2. A real effect study exists — outside the US, but real, peer-reviewed, and directly transferable
- **The team's own literature claim ("no rigorous US cost-benefit or effect study")
  appears correct for the US, but a rigorous peer-reviewed effect study exists for San
  Francisco**, using the *same kind of data the team is already using* (311 reports),
  which makes it an unusually clean benefit-transfer anchor.
- Study: Amato et al., "Somewhere to go: assessing the impact of public restroom
  interventions on reports of open defecation in San Francisco, California from 2014
  to 2020," *BMC Public Health*, 2022. Peer-reviewed journal article (tier 1).
  https://pmc.ncbi.nlm.nih.gov/articles/PMC9441075/ (accessed 2026-09-20, fetched and
  read directly).
  - Design: retrospective interrupted time-series, negative binomial regression on
    weekly 311 "Human/Animal Waste" report counts within 500m buffers around 27
    restroom locations (31 interventions), Jan 2014–Jan 2020.
  - Result: installing 13 new restrooms was associated with a statistically
    significant decline of **12.47 fewer weekly 311 waste reports** (p=0.0002) in the
    surrounding 500m area; a companion slope-change estimate also showed a significant
    post-intervention decline (-0.024, 95% CI -0.033 to -0.014).
  - Use for this project: (a) as a benefit-transfer coefficient — "X new restrooms in
    a comparable NYC area could plausibly reduce complaints by roughly this order of
    magnitude" — with the caveat that SF's population, climate, and unhoused-population
    context differ from NYC's and the effect size should not be imported without that
    caveat stated explicitly; (b) as direct evidence that 311 complaint counts DO
    respond measurably to restroom supply, which validates using 311 as an outcome
    metric for Problem A's own proxy-validation question (the team's WORKLOG already
    flagged "311 as partial validation, never verified" — this paper is exactly that
    verification, from another city).
  - There is also a companion medRxiv preprint (lower tier, preprint, same program)
    on reduced enteric pathogen hazards from the same Pit Stop program — noted but not
    opened in depth: https://www.medrxiv.org/content/10.1101/2023.02.10.23285757.full.pdf
    (accessed 2026-09-20, title/abstract only, **flag: preprint, not peer-reviewed**).

### B3. Benefit transfer and contingent valuation — exists, but not for this exact good
- Contingent valuation (stated willingness-to-pay via survey) is well established for
  valuing non-market sanitation improvements, but the published applications found are
  almost all in **developing-country rural/informal-settlement sanitation** (Vietnam,
  Bangladesh, Kenya, Malawi), not urban public-toilet amenity in a high-income city —
  context and magnitude would transfer poorly to NYC. No US or comparable-city
  contingent-valuation study of *public* (as opposed to household) toilets was found.
  **Flag: could not verify any WTP or CV study for public toilets in a US or
  comparable high-income city context** — this gap matches what the team already
  found. Representative source reviewed: FAO overview of CV in developing countries,
  https://www.fao.org/4/x8955e/x8955e03.htm (accessed 2026-09-20, tier: intl.
  agency report).
- Recommendation: do not pursue CV/WTP as a primary strategy — it requires fielding a
  survey the team does not have time or budget for, and no transferable estimate
  exists. Mention only as "considered, rejected for feasibility" if asked.

### B4. Value of Information / option value — real decision-analytic framing, standard concept
- Standard corporate-finance/decision-analysis idea: when a decision is at least
  partially irreversible and uncertainty is material, the option to run a **cheap pilot
  first** (e.g. one modular unit, one extended-hours trial) has quantifiable value
  because it lets the city learn the real effect size (using the same before/after
  311-count method as the SF study, B2) before committing capital to the full build-out.
  This directly turns "we cannot demonstrate an effect" into the recommendation itself:
  pilot + measure, using Amato et al.'s design as the template.
  Citation for the general framework (industry-standard summary, not academic primary
  source): Umbrex, "Value of Information Analysis," decision-making framework
  reference, https://umbrex.com/resources/frameworks/decision-making-frameworks/value-of-information-analysis/
  (accessed 2026-09-20, tier: consulting/practitioner summary — **for the deck, better
  to cite the academic real-options literature (e.g. Dixit & Pindyck, *Investment Under
  Uncertainty*, Princeton, 1994) as the canonical source; I did not verify page-level
  content of that book directly — flag as textbook citation by title only**).
- Difficulty: low to state as a recommendation ("pilot then measure, using the SF
  interrupted-time-series design on NYC's own 311 data"); this is arguably the project's
  strongest, most defensible final recommendation, combining B1 and B2.

### B5. International provision standards — real, numeric, citable
- **UK**: British Toilet Association guidance (as compiled by industry source
  loo.co.uk, citing British Standards): walking-distance standard of **max 300m
  spacing in the busiest areas, 500m generally in town centres**; fixture ratios of
  **1 cubicle per 550 women, 1 cubicle/urinal per 1,100 men, 1 accessible unisex
  cubicle and 1 baby-change per 10,000 population**; at least one facility in any
  settlement over 5,000 population. https://www.loo.co.uk/46/Toilet-Ratios (accessed
  2026-09-20, tier: industry compilation citing British Standards — **flag: did not
  independently verify the specific BS standard number; treat as good-faith industry
  summary, not primary standard text**).
  - **This 300-500m walking-distance standard is directly benchmarkable against NYC's
    own "5-minute walk" framing already used in the project (49.42% coverage figure)**
    — a 5-minute walk is roughly 400m, squarely inside the UK's stated range. That
    means the project can say "NYC's own stated standard is consistent with UK
    practice; the question is coverage against that standard, not whether the standard
    itself is reasonable" — turning it into direct benchmarking rather than needing an
    effect estimate.
- **ASEAN**: An ASEAN Public Toilet Standard document exists (2012) but I could not
  extract numeric ratios from it — the PDF did not parse as readable text in this
  session. **Flag: unverified, needs direct human review of
  https://www.asean.org/wp-content/uploads/2012/05/ASEAN-Public-Toilet-Standard.pdf**
  (accessed 2026-09-20, fetch attempted, content not extractable).
- **Singapore/Japan**: no formal numeric "toilets per population" standard was found
  for either in this search (Japan's provision is largely informal, via convenience
  stores; Singapore has a "Happy Toilet Programme" quality-grading scheme, not a
  provision-density standard). **Flag: could not verify a Singapore or Japan numeric
  provision standard** — do not cite a ratio for either without further, targeted
  search (e.g. Singapore's National Environment Agency or BCA code directly).

### B6. Additional US precedent found (not international, but relevant to B2/B5)
- Same BMC Public Health paper (B2) is the strongest single citation for the whole
  brief — it is simultaneously the missing US effect study (contra what the team's own
  research concluded — it exists for SF, just not a formal cost-benefit study) and a
  benefit-transfer anchor.

---

## Priority ranking for the team
1. **B1 (break-even/switching-value framing)** — rescues Problem B outright, cheap,
   uses data already in hand, backed by UK Treasury Green Book + standard CBA textbook.
2. **B2 (Amato et al. SF study)** — gives a real, peer-reviewed effect-size anchor and
   validates 311 as an outcome metric at the same time; also feeds directly into B4.
3. **B4 (pilot + measure using B2's method)** — turns the absence of proof into the
   recommendation itself.
4. **A3 (empirical-Bayes shrinkage)** — directly fixes the repeat-complainant distortion
   in Problem A, implementable in a few lines of R, no new data needed.
5. **B5 (UK walking-distance standard)** — free benchmark against NYC's own 5-minute-walk
   metric, no modeling required.
6. A1 (capture-recapture) — high value if a second list exists, but existence of that
   list is unverified; treat as a stretch idea pending a data check.
