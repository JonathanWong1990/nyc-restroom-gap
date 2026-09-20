# WORKLOG — shared ledger. READ FIRST, WRITE LAST.

**Every AI session working in this folder MUST use this file.** It is how parallel
and sequential sessions stay coherent. `00_START_HERE.md` tells you what is TRUE;
this file tells you what is HAPPENING and what happened recently.

---

## THE PROTOCOL (4 steps, do not skip)

**1. On pickup — READ.** Read `00_START_HERE.md`, then §CURRENT STATE below, then the
   3 most recent log entries. That is your full context.

**2. On pickup — CLAIM.** Before doing work, add a line to §ACTIVE CLAIMS with your
   session name, timestamp, and what you are touching. Other sessions may be running
   RIGHT NOW. If someone else has claimed your intended area, pick something else or
   coordinate through the human.

**3. During work — nothing required.** Do not narrate here as you go.

**4. On finish — WRITE.** This is the step that gets skipped. Do all three:
   - Append an entry to §LOG (newest at top, use the template)
   - Rewrite §CURRENT STATE so it is accurate as of now
   - Remove your line from §ACTIVE CLAIMS
   - **If you learned a durable fact** — a verified number, a new trap, a decision the
     human made — **also put it in `00_START_HERE.md`.** The log is history;
     `00_START_HERE.md` is the briefing. A fact that lives only in the log will be missed.

**Rules.** Append, never rewrite history. Record failures — what did NOT work is often
the most valuable entry. Never mark something done that you have not verified. If you
ran out of context mid-task, say so explicitly and say where you stopped.

---

## CURRENT STATE
*(Rewrite this section every session. It must describe NOW, not history.)*

**As of 2026-09-20, late session.**

- **Phase: ALL MODELLING COMPLETE.** Benchmark, causal (null), NB ranking regression,
  leaflet maps, logistic investment model, tree-vs-regression check, costed shortlist.
  Deck NOT started — the human wants the idea confirmed by the professor in text first.
- **BENCHMARK BEATEN.** NB regression scores 0.790 out-of-sample vs 0.710 for the subway-only
  rule, winning 94% of 200 splits. Scored table: `data_raw/model_nta_scored_20260920.csv`.
- **The bar any further model must beat: Spearman 0.713** (plain subway ridership vs observed
  complaints, 197 residential NTAs). Do not propose a model without reporting this number.
- **The causal route (Route C) is CLOSED.** Tested properly, twice, and it is null with a
  reasonably tight CI (-13% to +12%). Do not re-run it hoping for a different answer;
  read the log entry below first.
- **Unit of analysis: DECIDED** — residential 2020 NTAs (n=197), negative binomial with
  `offset(log(pop_total))`, SEs clustered by community district. CD (n=59) is the
  pre-committed robustness spec.
- **OPEN DECISION, blocking modelling:** Route A / B / C in `00_START_HERE.md` §4.
  The human has not chosen. **Do not pick for him.** Standing recommendation: C (causal
  DiD on the PIP natural experiment) as headline, B (G2SFCA) as the need-ranking layer.
- **All 5 research workstreams are COMPLETE.** Demand landed last; its hour-profile pull
  was deliberately stopped after 15 weeks (2025-09-01 to 2025-12-08) because it was
  marching toward a full year nobody needed. `notes/demand.md` is complete at 445 lines.
  The 15 raw week-parts in `data_raw/_hourprofile_parts/` (~57MB) still need collapsing
  into a station x hour x weekday/weekend table — that is a small, well-defined task.
- **Next action:** get the human's Route decision, then build the modelling table from
  `data_raw/nta_analysis_base_*.csv`, then run the one-liner benchmark BEFORE any model.
- **Nothing is broken.** No known failing code.

---

## EXTERNAL RESEARCH ROUND 2 (2026-09-20) — one objection ANSWERED, one claim WITHDRAWN

### ANSWERED: the "Starbucks objection" does not change the ranking. `R/96_commercial_supply.R`
1,886 geocoded chain food-service locations (Dunkin 629, Starbucks 267, McDonald's 192,
Subway 174, Popeyes 146, Chipotle 130, +7 more) from DOHMH inspections `43nn-pn8j`,
deduplicated on `camis`. 98.5% assigned to an NTA; median 7 per NTA, max 114, only 6 NTAs
with none. Saved as `data_raw/commercial_chains_dohmh_20260920.csv`.
- **Commercial supply is NOT associated with unmet need: IRR 1.075, clustered p = 0.394.**
  AIC gets slightly WORSE (1338 -> 1339).
- **The ranking is unchanged: Spearman 0.997, top-10 overlap 10/10.** Largest single move is
  ~17 places, deep in the list.
- **This is a defensive win.** The most predictable hostile question ("Midtown has a Starbucks
  on every block") has now been tested rather than conceded. Caveat to state: 13 chains only,
  no hotels, department stores or independents, and presence != permission to use.

### WITHDRAWN: the 53.45% vs 49.42% "credibility check" CANNOT BE MADE.
- **49.42% and "1 per 9,035" are NOT in the Council's *Good To Go?* PDF** — full text,
  footnotes, tables and appendix searched; neither string appears.
- They come from a separate **NYC Council dashboard**,
  https://council.nyc.gov/data/public-restroom-analysis/ ("973 Restrooms", "1 for every 9,035
  New Yorkers", "49.42% Access", figures as of November 2025).
- **The dashboard publishes NO methodology** — no walking speed, no distance threshold, no
  routing engine, no straight-line-vs-network statement, no population surface, no rule for
  overlapping service areas. Reverse-engineering the ratio implies a denominator of 8,791,055,
  which matches neither our ACS figure (8,483,844) nor the Census 2025 estimate (8,584,629).
- **Therefore our 53.45% cannot be validly compared to it.** Our page previously called this
  "the strongest credibility check in the project" and explained the 4pp gap as straight-line
  vs network distance. **That explanation was a guess and the comparison must be withdrawn.**
  Fix the evidence note (it wrongly attributes both figures to the PDF) and restate on the page.

### QUALIFY: "93rd of 100 largest US cities"
Traces to the Comptroller's 2019 *Dis-comfort Stations*, which cites **Trust for Public Land,
City Park Facts 2018** — a **park-system amenity inventory**, self-reported by organisations
and estimated where missing. It counts NYC's 1,428 **Parks bathrooms**, not citywide restroom
sites. No evidence all 99 peer cities used an identical facility-vs-fixture definition.
**Use only as a park-amenity comparison, with that qualification stated.**

### USABLE NEW MATERIAL
- **Scarborough Borough Council Public Toilets Strategy** (adopted municipal standard):
  "Toilets should be located with an assumed catchment area of 400 metres in high volume
  tourist areas" and "every urban area with more than 5,000 residents should have access to a
  public toilet". Replaces the unverified BTA 300m/500m claim — **BS 6465-4 exists and is the
  relevant standard but is paywalled; do NOT attribute spacing figures to it.**
- **City comparison, defensible but not a league table:** NYC 11.334 per 100k (973 operational
  sites / 8,584,629), Hong Kong 10.778 (811 FEHD toilets / 7,524,100), Paris 20.677 (435 /
  2,103,778). **NYC is NOT obviously worse than Hong Kong.** Definitions differ; say so.
- **IFS lead is DEAD** — household sanitation in India and Nigeria, not urban public toilets.
- Council report extras worth using: "More than one in ten surveyed restrooms (36 of 337), all
  located in parks, were closed during posted operating hours"; the Mayor's plan is to
  renovate 36 and build 46 restrooms in five years **against a gap of 1,147**.

## REBUILD COMPLETE (2026-09-20). THREE NEGATIVES, ONE STRONG POSITIVE.

### N1. The winterization causal design FAILS ITS OWN PLACEBO. Retire the causal claim.
`R/93_winterization.R`. 975 operational facilities (132 seasonal / 843 year-round), 250m
catchment around each FACILITY (not the tract), 2023-01..2026-06, collapsed to
facility x winter/non-winter, Poisson with facility FE, SEs clustered by facility.
569 facilities have any nearby summons (63 seasonal, 506 year-round).

| Spec | IRR | 95% CI | p |
|---|---|---|---|
| Urination summonses (MAIN) | **0.624** | 0.497-0.783 | <0.0001 |
| + park acreage x winter | 0.684 | 0.543-0.861 | 0.0012 |
| **PLACEBO: alcohol summonses** | **0.699** | 0.557-0.877 | 0.0020 |
| PLACEBO + park control | 0.714 | 0.571-0.892 | 0.0030 |

**The placebo moves almost as much as the outcome.** Seasonal restrooms sit where people
stop going in winter (parks, beaches, waterfront), so ALL summons types fall — it is a
population-seasonality effect, not a restroom effect. The park control only narrows it
(0.624 -> 0.684), confirming the confound is broader than parkland.
**This is a CLEAN kill: the design fails a pre-specified placebo.** Report it that way — it
is far stronger than "we found nothing."

### N2. Summonses do NOT corroborate the 311 ranking once enforcement is normalised.
`R/95_convergent_shortlist.R`. **Spearman(311 unmet need, enforcement-normalised summons
intensity) = 0.070.** Only 13 of 192 areas sit in the top quartile of both.
**Our top 311 picks have no corroboration:** Brighton Beach 100th percentile on 311 vs 14th
on summonses; Williamsbridge-Olinville 98 vs 17; Dyker Heights 96 vs 5.
The earlier "convergent top-25" was computed on RAW counts and was therefore an
enforcement/volume artifact. **Do not present it as convergent validation.** The honest
statement: the two instruments disagree, so the ranking rests on 311 alone.

### N3. Summonses fail as a ranking outcome (below, unchanged).

### P1. BREAK-EVEN ANALYSIS WORKS, and it reframes the whole business case.
`R/94_breakeven.R`. Median NYC restroom project $1,559,000 -> **$109,693/yr** (20yr, 3.5%).
- **Justifying a restroom by avoided complaints is IMPLAUSIBLE.** At $50 per avoided
  incident you need **2,194 avoided incidents per year at one facility**. NYC's ENTIRE
  citywide complaint volume is ~540/yr. Even at $1,000 per incident you need 110/yr.
  **The nuisance-reduction business case cannot close. State this plainly.**
- **The service business case closes easily:** at 200 uses/day the cost is **$1.50 per use**;
  at 400 uses/day, **$0.75**.
- **=> THE CORE MANAGERIAL REFRAME: public restrooms are not a nuisance-reduction
  investment, they are a service. Complaints tell you WHERE demand is unmet; they cannot
  justify WHETHER to build. That reframe is supported by our own numbers and it dissolves
  the "you have no ROI" objection rather than dodging it.**
- Local Law 58 gap: 1,147 facilities x $1.56M = **$1.79 billion, about $211 per NYC resident.**

## REBUILD RESULT: SUMMONSES FAIL AS A RANKING OUTCOME. Keep 311.

`R/91_rebuild_outcome.R`, `R/92_rebuild_model.R` -> `data_raw/model_v2_*`. Ran it; it does
not work, and the reason is worth more than the attempt.

**The enforcement contamination is fatal for LEVELS.**
- cor(urination summonses, alcohol summonses) across 197 NTAs = **0.890 raw, 0.951 Spearman.**
- Enforcement intensity ALONE explains McFadden R2 **0.151** of the full model's **0.175** —
  i.e. **~86% of the model's explanatory power is just "where do police write summonses".**
- **Out-of-sample, the model LOSES to enforcement alone: 0.919 vs 0.941, beating it in only
  3% of 200 splits.** It beats the subway benchmark 100% of the time, but that is the wrong
  benchmark — for this outcome the benchmark IS enforcement, and we lose to it.
- Normalising to a share drops cor(share, alcohol) to 0.110, but a share is not a count model
  and the ranking it produces is unstable: **6 of the top 12 have fewer than 10 summonses**
  (median 18 vs citywide 33). Not systematically small-denominator driven
  (Spearman(log ratio, log pred) = 0.029) but individual entries are noise.
- **The two rankings disagree almost completely: Spearman 0.142, top-10 overlap 0/10.**

**CONCLUSION — do not swap the outcome.** 311 remains the ranking outcome. A summons map is a
policing map. Swapping would have replaced a known reporting bias with a worse, less
defensible one, and the 7x density gain is illusory because the extra events carry
enforcement signal, not need signal.

**WHERE SUMMONSES ARE STILL VALUABLE (both survive this result):**
1. **Convergent validation.** Where 311 and summonses BOTH rank an area high, need is visible
   to two oppositely-biased instruments. That list (Jackson Heights, East Harlem North,
   Elmhurst, Bed-Stuy West, Midtown, Hell's Kitchen, Bushwick West, Corona, Jamaica,
   Chelsea) is a defensible confident shortlist and is a slide we did not previously have.
2. **The causal test.** Enforcement contaminates LEVELS, not CHANGES. A within-facility
   before/after design differences out a precinct's enforcement intensity, so the winterization
   DDD (MDE +/-9.3%) remains the right use of this data. Plus the alcohol placebo.

**For the deck:** this is a genuine methodological finding, not a failed detour. "We found a
denser outcome measure, tested it properly, and rejected it because it measures policing
rather than need" is exactly the discipline the benchmark habit exists to enforce.

## KNOWN DEFECTS — FIX BEFORE ANY NUMBER GOES ON A SLIDE
*(From the 2026-09-20 adversarial audit. Nothing below is fixed yet.)*

1. **DiD treatment is ~93% mismeasured.** `closed_flag = nzchar(closed)` counts ANY non-empty
   PIP construction text as a closure. Verified: only **151 of 2,057** flagged rows (7.3%) are
   `Closed / No Construct.`; 1,702 are `Partial Constr./Rest of Site Rated` — which explicitly
   means the site WAS inspectable. Fix: `grepl("^Closed", trimws(closed))`. Re-run drops the
   sample from 278 parks to **44** and the estimate to +0.001 (z=0.01) — still null, so the
   CONCLUSION survives, but "we tested 278 parks" is false and the null is underpowered.
2. **STOCK/FLOW ERROR: `events_311` is a 6.71-year cumulative count** (2020-01-02 to
   2026-09-18) divided by an ANNUAL cost. Every $/complaint figure is understated 6.71x.
   Blended is **$20,832**, not $3,105. Annual excess is **72**, not 483.
3. **Headline comparison is a category error AND we lose it.** One comfort station annualised
   (30yr @3%) = **$193,516/yr** vs our $1,293,669/yr — we are 6.7x MORE expensive. Restate
   capital-to-capital: **"$11.3M of capital (three comfort stations) + $511k/yr covers 27
   neighbourhoods instead of one site"** (11,284,000/3,793,000 = 2.97).
4. **The hours recommendation is partly an artifact of Parks boilerplate.** Verified:
   **525 of 843** operational facilities (62.3%) carry the placeholder string
   `"8am-4pm, Open later seasonally"`, which parses to a flat 8h and trips the `med_hours < 9`
   rule. Cannot claim these facilities close early.
5. **"Reconstruct or repair" is priced as component work** ($60,500) though the ladder puts
   reconstruction at $1,152,500 (19x). Correct it and the top-5 INVERTS; total rises 79%.
6. **The wage sensitivity is vacuous.** Breakeven is **$4.86/hr**, so $20/$35/$60/$100 all sit
   on the same side of it. Remove the claim; it is not robustness.
7. **Phone-only ranking breaks half the top 6.** East Harlem 4->41, Williamsbridge 5->52,
   Astoria(E) 6->123. Top-10 overlap 4/10. Narrow the claim to the robust subset.
8. **"21 open at 11pm Saturday" is wrong — it is 40** (21 is open PAST 11pm). **"9 are
   24-hour" is 8**, which exactly matches the Council figure, so that corroboration gets
   STRONGER. Fix both.
9. **500m park buffers double-count:** 1.73x multiplicity, 46.3% of events attributed to 2-6
   parks. Point estimate survives; SEs are understated and spillover is not ruled out.
10. **120 of 843 restrooms (14%) are dropped** from the `restrooms` covariate because they sit
    in non-residential NTAs, while `coverage` uses all 843 — two supply measures disagree
    inside one `case_when`. Flips East Flushing from 0 restrooms to 1.
11. **Threshold instability:** total ranges $948k-$1.64M across a 27-combination grid; only
    1 of 9 "build" recommendations is driven by an actual absence of restrooms.
12. **Dedupe on `incident_address` collapses street-name-only rows** (12.4% have no house
    number; "BROADWAY" spans 20km). East Harlem 99 -> 81 under coordinate-based dedupe.

13. **The logistic model runs BACKWARDS IN TIME.** 76% of the 191 restroom capital projects
    have `designstart` before 2020-01-01, but `need` is built from 2020-2026 complaints. A 2012
    project cannot respond to 2023 complaints. Also `need` is a first-stage residual — a
    generated regressor — so its printed SE and p=0.108 are not valid. Fix: restrict to
    designstart >= 2020, or reframe the whole model as description, not selection.
14. **DiD treatment is interpolated from a twice-yearly snapshot.** Median inspection gap is
    **148 days**; carry-forward inflates the closed share from 6.5% of inspections to 17.6% of
    park-months. Non-classical measurement error in a binary treatment attenuates toward zero —
    **this alone could manufacture the null.**
15. **It is not a staggered DiD, it is a REVERSING one.** Mean 3.25 switches per park; 83%
    switch more than once (max 26). Goodman-Bacon is the wrong citation; cite
    de Chaisemartin-D'Haultfoeuille. Negative weights are worse under reversal.
16. **The null is UNDERPOWERED, not precise.** MDE at 80% power = **+20.5% / -17.0%**. Never
    say "tight" or "precise"; say "we cannot detect anything smaller than about a fifth."
    Same for the restroom coefficient: IRR CI per doubling is 0.889-1.126.
17. **`offset(log(pop_total))` is rejected by the data.** Freeing it: beta = 0.662 (SE 0.129),
    H0 beta=1 gives z=-2.62, **p=0.009**. Complaints scale sub-proportionally with residents.
    Ranking survives (Spearman 0.975, 9/10 top-10 overlap), so keep the offset for
    interpretability but REPORT the test.
18. **"Parkland predicts, need does not" accepts the null.** need OR 1.52, **95% CI 0.92-2.57**
    — consistent with need mattering substantially. Parkland is also near-tautological (Parks
    projects only occur in parks) and its gradient is NON-MONOTONE (Q1 30%, Q2 47%, Q3 59%,
    Q4 49%). Correct phrasing: "parkland is estimated precisely, need is not."
19. **Ratio vs excess disagree and both are needed.** Rank correlation only 0.887. Midtown is
    **2nd by excess count (+40.5) but 12th by ratio**. The ratio answers "most underserved per
    unit of demand"; the excess answers "biggest absolute deficit" — **a build decision needs
    the second.** Show both columns. Also a gamma lower bound demotes **Hunts Point to 0.93**,
    the only top-12 entry not reliably above expectation.

20. **WE CLAIM CLUSTERED SEs WE NEVER COMPUTED.** `R/20_regression.R` uses plain `glm.nb`
    standard errors; `grep -rln "cluster_se|vcovCL|clustered" R/` hits only the two DiD scripts.
    The write-up says "standard errors clustered by community district". **Under real
    clustering by cdta2020, hotels moves p=0.040 -> p=0.100** — the "jobs and hotels all
    predict" sentence does not survive the method we claim. Either cluster and drop hotels
    from that sentence, or delete the claim. This is a methods-integrity issue, fix first.
21. **"3.99B taxi trips" double-counts.** `c5iv-bn4s` holds BOTH Drop-off (1,996,563,901) and
    Pick-up (1,992,929,574) rows for the same trips. True volume ~**2.0B trips** (3.99B trip
    ENDPOINTS). Restate as endpoints or halve it.
22. **"Midtown-Times Square has the highest raw complaint count in the city" is FALSE.**
    Deduped NTA: East Harlem (North) **99** > Midtown 84. Raw: East Harlem 403, Far Rockaway
    353, Astoria 187 — Midtown is not top five. Midtown IS #1 at COMMUNITY-BOARD level
    (05 Manhattan, 143). **The doc mixes CB-level and NTA-level results.** Rewrite the
    pull-quote to say "the busiest community district in Manhattan" or drop it.
23. **Cost figures $3,793,000 / $1,152,500 are HARDCODED, not derived.** No script computes
    them; `notes/supply.md` says n=59 new / n=130 reconstruction (sums to 189, ties to neither
    191 projects nor the 128 that parse to a number — 33% are banded text, silently dropped).
    An independent classification gives n=42 / median $3.66M and n=142 / median $848,500.
    **$3,793,000 is the denominator of the headline.** Derive it in a script or stop citing it.
24. **The 0.709-vs-0.487 comparison is apples-to-oranges.** 0.709 is the out-of-sample mean
    over 200 splits; 0.487 is in-sample full-data. Like-for-like in-sample benchmark = 0.713.
25. **`notes/outcome_count_reconciliation.md` arithmetic does not add up.** 3,738 - 122 = 3,616,
    not 3,629. The 122 is the PRE-dedup row drop; the post-dedup drop is **109**. Fix the note.
26. **Footer says 3,629 across 197 residential NTAs; the modelled total is 3,556** (3,623
    survive the NTA join; 67 land in non-residential NTAs).
27. **"2.2 inspections/year" is 1.87 mean / 2.04 median.** **"20 years of inspections" is 22.1.**
28. **The deduped top-ten list names only nine** — Upper East Side (08 Manhattan, 130) missing.
29. **"$875k-$5M per bathroom" is a constructed range.** $875k is blog-tier (the evidence note
    says "corroborating, not sole source"); $5M is the BOTTOM of a separate "$5M-$10M" range.
30. **Coverage is AREA-weighted, not resident-weighted** (uniform-population-within-tract
    assumption). Attributing the entire +4.03pp gap to straight-line-vs-network distance is an
    unverified guess that happens to flatter us; the 843-vs-973 facility filter and the uniform
    assumption are at least as likely contributors. Hedge it.
31. **Two reproducibility bugs.** `61_cost_annualised.R` prints `$NA` (missing `na.rm=TRUE`;
    the $1,293,669.21 total is correct but not emitted). `11_benchmark.R` **errors on any
    re-run** — line 58 writes `oneliner` back into the file line 6 reads, so the second run
    gets `oneliner.x`/`oneliner.y`. The footer claims "reproducible from the repository".
32. **"No pre-trend" overstates.** Pre-period bins are **+12.2% (z=0.97)** and **+24.1%
    (z=0.91)** and the six bins decline monotonically. Not significant, but not small either.

**VERIFIED CORRECT (do not re-audit):**
- **The model result is SEED-ROBUST.** Six seeds and 5,000 splits: NB 0.786-0.795, benchmark
  0.702-0.714, NB wins 92-98%. Not an artifact. (Note: "tree beats benchmark in only 55%" is
  the seed-6093 low end; across seeds it is 55-65%, and the tree's MEAN rho 0.720 exceeds the
  benchmark's 0.709 — "the tree lost" is a win-rate framing, say so.)
- All IRRs, the full top-6 unmet-need table, coverage 53.45%/38.75%, the DiD estimate and CI,
  every logistic OR conversion (poverty 2.00 per 10pp, parkland 1.34 per doubling), the
  $1,293,669.21 total and $3,105 blended figure, and all item-7 descriptives reproduce exactly.
- **No published figure comes from the evidence note's six "thin ice" items.** That discipline
  held.
- **`cluster_se()` IS CORRECT.** Independently rebuilt CR0: **0.066472 vs script 0.066472**.
  For a log-link Poisson the score is X'(y-mu), so `type="response"` is right. Optional: add
  Stata's CR1 factor (N-1)/(N-K)=1.017 -> 0.0670. Do NOT reuse this function on glm.nb.
- **No multicollinearity.** Max GVIF 5.28 (poverty); l_sub 2.24, l_jobs 2.90, l_hotel 2.56.
- **`resid_ratio` is NOT small-denominator-driven.** Spearman(log ratio, log pred) = -0.023;
  rank corr with Pearson residual 0.996; bootstrap top-10 overlap 8.1/10. Brighton Beach and
  East Elmhurst are genuine.
- **The benchmark comparison is fair and mildly SELF-PENALISING.** A trained 1-variable NB
  scores 0.705 vs raw subway 0.702; the full model beats that in 97% of splits.
- **The tree is not handicapped — it is favoured.** Rate x pop 0.724 was the best of three
  specs (count-tree 0.660, unscaled 0.628); NB beats the count-tree in 99% of splits. every distance constant (`400/0.3048`, `500/0.3048`)
across all 24 scripts; `st_within` vs `st_intersects` identical; facility_id alignment 843/843
(works, but fragile — build the id before the coordinate filter); hours parser 12/12
spot-checks incl. the AM/PM repair; capital tracker 247 rows -> exactly 191 trackerids;
NTA table exactly 197 rows, no zero-pop survivors, `events_311` = cleaned series; no zero in
the modelling table is a join failure.

## BREAKTHROUGH — A SECOND INDEPENDENT OUTCOME MEASURE (2026-09-20)

**NYPD OATH summonses `hxbk-grd3`** (data.cityofnewyork.us), pulled to
`data_raw/nypd_oath_urination_hxbk-grd3_20260920.csv`, verified in `R/90_two_signals.R`.

- 27,384 rows, `law_desc = 'PUBLIC URINATION'` (27,100) + park urination (284). **A clean
  CODED field — no free-text parsing.** 2023-01-01 to 2026-06-30. **100% geocoded.**
- De-duplicated to coordinate-month: **14,534 events on the 197 residential NTAs**, median 30,
  12 zeros — against 311's **2,033**, median 6, over the same window. **7.1x the event density.**
- **This is a genuinely INDEPENDENT mechanism.** 311 = a citizen chooses to call. OATH = an
  officer writes a summons. The online-filing bias (r=0.597) that broke half our 311 ranking
  cannot touch it.
- **Agreement is only MODERATE: Spearman 0.499, top-10 overlap 4/10, top-25 overlap 10/25.**
  Report that honestly — it is the point, not a flaw. Two biased instruments that disagree
  bracket the truth; where they AGREE, need is real rather than an artifact of who is heard.
- **NON-NEGOTIABLE CAVEAT:** raw summons counts track enforcement intensity —
  `cor(urination summonses, ALL OATH summonses)` across 78 precincts = 0.761 raw, **0.892
  Spearman**. **Never model the raw count.** Use the share (urination / all OATH in precinct,
  range 0-0.201, median 0.083) or control for `log(all OATH summonses)`. The signal survives
  normalisation: precincts 115 Jackson Hts 20.1%, 025 E Harlem 19.9%, 110 Elmhurst 17.4% top
  both raw and normalised.
- **Convergent top-25 (in BOTH measures):** Jackson Heights, East Harlem (North), Elmhurst,
  Bedford-Stuyvesant (West), Midtown-Times Square, Hell's Kitchen, Bushwick (West), Corona,
  Jamaica, Chelsea-Hudson Yards.
- **THIS MAY RESOLVE THE THESIS/PAYLOAD TENSION.** Those ten are commercial, transit and
  nightlife districts — i.e. STREET geography, which is what our thesis argues. The 311-only
  residual ranking pointed at outer-borough RESIDENTIAL areas (Brighton Beach, East Flatbush,
  Williamsbridge), and only East Harlem (North) appears in both lists. Worth testing whether
  the 311-only list was substantially a reporting artifact all along.

**Also found:** SLA active liquor licences `9s3h-dpkz` (24,874 in NYC, 98% geocoded) — a
nightlife covariate for the 18:00 peak. NYPD criminal court summonses `sv2w-rv3k` (historic,
free-text, collapsed after the 2016 Criminal Justice Reform Act) — usable as a pre-period only.
PIP `visitorcount` — 68,751 usable rows but a spot count (median 2 visitors, 39% of sites
median 0); use to weight which comfort stations actually serve people, not as citywide demand.
**DEAD:** MTA station cleanliness/restroom reopenings (no such dataset), OSM toilets (only 38
tagged customer-access, does not solve the Starbucks objection), Refuge Restrooms (stale).

## IDENTIFICATION: powered at last, and the first answer is CONFOUNDED not null (2026-09-20)

**The blocker was never the design — it was the outcome variable.** Rebuilding on OATH
summonses roughly HALVES every minimum detectable effect in the project.

**A built-in placebo outcome exists and it is a major asset.** Same dataset:
`UNLAWFUL CONSUMPTION/POSSESSION OF ALCOHOLIC BEVERAGES`, **163,329 rows** — same officers,
same shifts, same blocks, but NOT restroom-dependent. This defeats the standard objection that
summons data measures policing rather than behaviour. Saved as
`data_raw/nypd_oath_alcohol_placebo_hxbk-grd3_20260920.csv`.

**Designs, ranked by achievable power (all ESTIMATED, not proposed):**
| Design | Outcome | MDE | Verdict |
|---|---|---|---|
| Winterization triple-difference | OATH summonses | **±9.3%** | **only presentable option** |
| Winterization DiD | 311 | ±22.6% | same as the failed PIP DiD |
| Capital-tracker construction windows | 311 | ±52.5% | DEAD — 83 completions, 312 treated events |
| Hours-as-treatment | 311 | ±87% | DEAD, and wrong-signed |
| PIP as winterization validator | — | — | DEAD — cannot date winterization |

**THE RESULT: DDD = -0.077 (SE 0.033, p=0.019, IRR 0.926) — WRONG-SIGNED.** Closing the
restroom associates with FEWER summonses. Do not present this as a finding.

**Why, and this is the valuable part — it is CONFOUNDING, not noise:**
- The restroom-presence placebo is CLEAN: year-round dose x winter = -0.001 (CI 0.973-1.020).
  The design does not manufacture seasonal effects from restroom proximity alone.
- The park-seasonality placebo FAILS: park acres within 800m x winter = **-0.225 (p=0.002)**.
  Conditioning on it collapses the seasonal effect from -0.086 to **-0.050 (p=0.20)**.
- Reading: **winterized restrooms sit in parks that empty in winter.** Tract x month FE absorbs
  tract-level footfall but not the within-tract shift from park interior to street.

**NEXT STEPS (in order):** (1) rebuild every existing model on the OATH outcome — a drop-in
replacement that halves every MDE; (2) attack the park confound by narrowing the catchment to
**200-250m around the restroom itself** rather than the tract centroid, so park interior and
surrounding street are not pooled; (3) use the alcohol placebo throughout.

**Also killed: the hours recommendation as currently framed.** 641 of 975 facilities carry the
`8am-4pm, Open later seasonally` boilerplate; the 202 with genuine day-of-week variation give a
**wrong-signed IRR 1.54** — restrooms are open precisely when areas are busy. The "10
neighbourhoods just need longer hours" line cannot survive as an empirical claim; it can only
survive as a cost argument.

## ACTIVE CLAIMS
*(Add yourself on pickup, remove yourself on finish. Stale claims >1 day old can be
cleared by the next session — note it in the log when you do.)*

- *(none — folder is free)*

---

## LOG
*(Newest first. Template below; copy it.)*

```
### YYYY-MM-DD — <session name or "unnamed"> — <one-line headline>
**Did:** what you actually changed or produced, with file paths.
**Found:** facts worth knowing. Numbers, not vibes.
**Failed / ruled out:** what did not work. Do not omit this.
**Left undone:** where you stopped and why.
**Next:** what the following session should do first.
```

---

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — AUDIT: ranking is only PARTLY robust to reporting bias
**Did:** `R/70_audit_checks.R`, run in response to adversarial review. Two checks the review
said were missing: time-of-day of complaints, and the phone-only reporting-channel sensitivity
test that had been promised but never run.
**Found — CHECK 2 IS THE SERIOUS ONE:**
- **Half the published top 6 do NOT survive a phone-only ranking.** Rank on all channels vs
  phone-only: Brighton Beach 1->2 OK, East Flatbush-Rugby 3->1 OK, East Elmhurst 2->5 OK, but
  **East Harlem (North) 4->41, Williamsbridge-Olinville 5->52, Astoria(E)-Woodside(N) 6->123.**
  Top-10 overlap is only **4 of 10**; Spearman between the two rankings 0.713.
  Phone is 36.8% of events (1,344 of 3,629). **The published priority list is partly an
  artifact of who files online.** This MUST be disclosed and the claim narrowed.
- **CHECK 1 refutes the reviewer's premise but HELPS the hours argument.** Complaints are NOT
  nocturnal: 00:00-05:59 is only **5.7%**; the peak hour is **18:00** (257), then 13:00, 17:00.
  Afternoon 12:00-17:59 = 36.9%, evening 18:00-23:59 = **29.9%**, morning 27.5%.
  BUT facility availability collapses exactly across that evening peak: ~797 of 843 open at
  15:00, **143 at 18:00, 49 at 21:00, 21 at 23:00**. So ~30% of complaints occur in a window
  when 83-97% of facilities have shut. **This is the strongest quantitative argument for the
  hours recommendation and it is currently nowhere in the write-up.**
**Failed / ruled out:** My first version of this script had two bugs I caught and fixed —
a regex built from truncated names containing an unescaped "(", and a facilities-open
denominator that counted all 1,066 facilities instead of the 843 operational+year-round
(it printed "917 of 843").
**Left undone:** Write-up not yet corrected for either finding. 4 audit agents still running.
**Next:** Narrow the ranking claim to the channel-robust subset; add the evening-gap finding.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — ALL MODELS DONE: tree check + costed shortlist
**Did:** `R/50_tree_vs_regression.R` (Session 7 comparison), `R/60_cost_layer.R` (intervention
assignment), `R/61_cost_annualised.R` (fixed cost model + sensitivity). Outputs:
`data_raw/model_nta_interventions_20260920.csv`, `model_shortlist_costed_20260920.csv`.
**Found:**
- **Session 7 check: regression WINS.** Out-of-sample Spearman — NB regression 0.793,
  decision tree 0.720, pruned tree 0.713, benchmark 0.709. Regression beats the tree in
  **94%** of splits; the tree beats the dumb benchmark in only 55%. Textbook small-n
  overfitting (n=197). Present this honestly — it demonstrates train/test discipline.
- **Shortlist = 29 neighbourhoods at unmet-need ratio >= 1.5** (27 costable). Intervention mix:
  10 extend hours, 9 build/modular, 8 reconstruct-or-repair, 2 already served.
- **TOTAL $1,293,669 PER YEAR to address all 27 — versus $3,793,000 for ONE traditional
  new-build comfort station.** The entire shortlist costs 0.34x one comfort station, annually.
  Blended cost $3,105 per excess complaint per year. This is the headline economic number.
- **SENSITIVITY: the top-5 ranking is IDENTICAL at $20, $35, $60 and $100/hr staffing**
  (East Elmhurst, Williamsbridge-Olinville, Far Rockaway-Bayswater, Tribeca-Civic Center,
  Bushwick West). The recommendation does NOT depend on the one number we could not source.
**Failed / ruled out:**
- **I reproduced the teammates' own bug first.** Setting hours-extension CapEx to $0 made
  cost-per-complaint $0, so it mechanically won everywhere — exactly the `SROI = NPV/CapEx`
  flaw we criticised. Fixed by annualising ALL options (modular 20yr, repair 10yr, 3% discount)
  and pricing hours as incremental staffing. **Never compare a $0-CapEx option on a CapEx ratio.**
- **No citable operating cost exists.** The only NYC figure is Bryant Park at $271,000/yr,
  which the evidence file explicitly flags as unusable as a baseline (attended, flowers,
  premium). Staffing is therefore an EXPLICIT labelled assumption ($35/hr x 4h/day x 365),
  defended by the sensitivity above — do not present it as sourced.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — LOGISTIC investment model: parkland predicts, need does not
**Did:** `R/40_logistic.R` -> `data_raw/model_nta_investment_20260920.csv`. Outcome = did an
NTA receive a Parks capital RESTROOM project (91 of 197 did). Session 6 technique: logistic
regression + out-of-sample confusion matrix (200 x 70/30 splits).
**Found:**
- **Parkland predicts investment (OR 1.34 per doubling of acreage, p=0.005). Measured need
  does NOT (OR 1.52 per unit of unmet-need ratio, p=0.108 — positive but NOT significant).**
  Subway ridership also significant (OR 1.13, p=0.016).
- **Poverty strongly predicts investment: OR 2.00 per +10 percentage points (p=0.002).** NYC
  IS investing in poorer neighbourhoods. Do not run an "NYC ignores the poor" narrative —
  the data refutes it. The real story is CATEGORY of place (parks), not class.
- Out-of-sample accuracy 0.604 vs a 0.538 majority-class baseline. Beats it, but modestly —
  report both numbers, do not quote accuracy alone.
- **Midtown-Times Square appears on the high-need/no-investment list** (84 complaints, 1.93x
  unmet need). Not because it is ignored, but because Parks capital projects only reach
  PARKS — and Midtown has almost none. This is the thesis in one row.
- Actionable list (high need, zero investment): Brighton Beach 3.82x, New Dorp-Midland Beach
  2.76x, Hunts Point 2.36x, Brooklyn Heights 2.12x, East Flushing 2.07x (ZERO restrooms).
**Failed / ruled out:** `need` is not significant at p<.05 — do NOT claim "investment is
blind to need". The defensible claim is weaker and still strong: parkland predicts investment
MORE RELIABLY than need does.
**Left undone:** tree-vs-regression honesty check, cost layer, deck.
**Next:** cost/intervention layer, then the deck.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — MAPS BUILT + coverage metric independently validated
**Did:** `R/30_maps.R` -> `outputs/map1_unmet_need.html` (NTA choropleth of model residual +
843 restroom points) and `outputs/map2_coverage_gap.html` (5-min-walk coverage + 426 subway
complexes, red = no restroom within 400m). `R/31_coverage_validation.R`.
**Found:**
- **VALIDATION: our population-weighted 5-min-walk coverage = 53.45% vs NYC Council's
  published 49.42%.** Within 4pp, computed independently from raw data. The gap is explained
  and expected: we use straight-line 400m buffers, the city almost certainly uses walking-
  NETWORK distance, which is always shorter-reaching. Ours should be HIGHER, and it is.
  This is the strongest credibility check in the project — quote it.
- Land-area coverage is only **38.75%** vs 53.45% population-weighted. Use the
  population-weighted one; land-area flatters nothing and is not comparable to the city's.
- **158 of 426 subway complexes (37%) have no operational restroom within 400m.**
- **Coverage is NOT the binding constraint everywhere.** East Harlem (North) has **78%**
  coverage yet 2.98x unmet need; Brighton Beach has 38% coverage with ONE restroom. So the
  fix differs by place — capacity/hours/quality in East Harlem, absent supply in Brighton
  Beach. This directly motivates the "what kind of intervention" stage.
**Failed / ruled out:** `saveWidget(selfcontained=TRUE)` needs pandoc, which is NOT installed.
Maps are written with `selfcontained=FALSE`, so each .html has a sibling `*_files/` folder —
keep them together when sharing, or install pandoc.
**Left undone:** logistic selection model, tree-vs-regression check, cost layer, deck.
**Next:** logistic "does NYC invest where need is" model.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — RANKING MODEL WORKS. Beats benchmark out of sample.
**Did:** `R/20_regression.R` — negative binomial, 197 residential NTAs, offset(log pop),
borough dummies. Outputs `data_raw/model_nta_scored_20260920.csv`, `model_nb_20260920.rds`.
**Found:**
- **BEATS THE BENCHMARK: out-of-sample Spearman 0.790 vs 0.710**, across 200 random 70/30
  splits, winning **94%** of them (mean margin +0.080). The model earns its complexity.
- Significant predictors (IRR): subway riders 1.063 (p<.001), jobs 1.151 (p=.050),
  hotels 1.124 (p=.040), share 65+ **0.964 (p<.001, protective)**, Manhattan 2.119 (p<.001),
  Queens 1.651 (p=.001). theta=4.48, McFadden pseudo-R2 = 0.119.
- **KEY RESULT: restroom count coefficient is ZERO once demand is controlled** (IRR 1.001,
  p=0.99). The raw +0.304 correlation was pure confounding. Existing supply neither helps
  nor hurts — consistent with the DiD null and with the "restrooms are in parks, need is on
  streets" story. Three independent routes now point the same way.
- **The ranking ANSWER CHANGES when you use residuals instead of raw counts.** Raw counts say
  Midtown. Complaints-relative-to-predicted says **Brighton Beach (3.82x), East Elmhurst
  (3.57x), East Flatbush-Rugby (3.18x), East Harlem North (2.98x), Williamsbridge-Olinville
  (2.94x), Astoria East-Woodside North (2.78x)** — outer-borough, low-supply, non-touristy.
  This is a genuinely different and more defensible answer than either the teammates' index
  or the one-liner.
**Failed / ruled out:** Income, poverty, population density all insignificant once demand and
borough are in. Do not oversell an equity story from THIS model — the equity signal is in
age (65+) and in which areas get capital projects, not in income.
**Left undone:** Maps (Session 5), logistic selection model, tree-vs-regression comparison,
cost layer, deck.
**Next:** Leaflet maps, then the logistic "where does NYC actually invest" model.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — FIRST MODELS RUN. Benchmark set; causal test is NULL.
**Did:** Built `R/10_modelling_table.R` (197-NTA table, all joins cardinality-checked),
`R/11_benchmark.R` (one-liner benchmarks), `R/12b_did_feasibility2.R`, `R/13_did_panel.R`
(519-park x month panel), `R/14_did_estimate.R` (TWFE Poisson + event study),
`R/15_did_openings.R` (second treatment). Outputs: `data_raw/model_nta_table_20260920.csv`,
`did_panel_20260920.rds`.
**Found:**
- **BENCHMARK TO BEAT = plain subway ridership, Spearman 0.713 vs observed complaints.**
  My "clever" one-liner (riders at stations with no restroom within 400m) scored only 0.487
  — WORSE than the dumb rule. Jobs 0.622, hotels 0.559, population 0.561.
- **Restroom count correlates POSITIVELY with complaints (+0.304).** Supply is placed where
  demand already is. Any naive cross-sectional model concludes NYC should REMOVE restrooms.
  This is the single best justification for a causal design, and a strong slide.
- **CAUSAL TEST IS NULL.** TWFE Poisson, 21,529 park-months, 278 parks with closure variation:
  coef(closed) = -0.0122, clustered SE 0.0665, **p = 0.85**, 95% CI **-13.3% to +12.5%**.
  Event study shows no pre-trend and no post-effect (all |z| < 1.6). This is a reasonably
  PRECISE null — it rules out effects larger than about ±13%.
- Second treatment (capital-project completion, restroom projects only, n=63 completions /
  45 identifying sites): coef 0.2123, p=0.38, CI -23% to +99%. **Underpowered, uninformative.**
**Failed / ruled out:**
- **The supply workstream's "584 sites switch closed status" was described wrongly.**
  `csnumber` has only **3 distinct values** — it is NOT a comfort-station ID. `closed` is NOT
  a Y/N flag; it is free-text construction status, **blank in 93.5% of rows**. The claim only
  holds at `prop_id` level with closed = "any non-empty construction/closure text"
  (2,254 events / 564 sites). Corrected in code; do not trust the original phrasing.
- Inspections occur only **2.2x/year**, so closure dates are known to within ~6 months. This
  attenuates any DiD and is a real limitation, not a fixable one.
- First run of `15_did_openings.R` accidentally used ALL 2,273 park capital projects. Only
  **191 are restroom projects**. Fixed; both versions were null anyway.
**Left undone:** Route B (G2SFCA) not built. No predictive model yet beating the 0.713 bar.
**Next:** Pivot the headline away from causal. Build a predictive/ranking model that must
beat Spearman 0.713, and use the null as an honest, genuinely interesting finding.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — demand workstream complete, stopped early
**Did:** Stopped the demand agent after ~50 min. Its write-up was already complete; it was
still pulling MTA weeks one per ~40s with no stopping condition. Promoted its findings into
`00_START_HERE.md` (§5 Demand block, traps 14-17) and added a "bound every pull" section to
`CONVENTIONS.md`.
**Found:** Strong measures — subway monthly `ak4z-sape` (426 stations, 2017-2026), taxi/FHV
`c5iv-bn4s` (3.99B trips summarised), **LODES workplace jobs (4.59M jobs)**. Hotels are the
ONLY defensible tourist-presence variable. Cultural orgs `u35m-9t32` is a grants roster
(only 99 Museum rows of 2,535) — **do not use as density**. Pedestrian counts are 114
screenlines citywide: validation-only, but a real 19-year series.
**Failed / ruled out:** `kcrm-j9hh` museums is a non-tabular map asset (no API row access);
`mzbd-kucq` Places is stale since 2013; `buis-pvji` landmarks is wrong construct
(designation != footfall). `httr::GET` reports phantom connection failures on heavy
aggregations — helpers now shell out to `curl`.
**Left undone:** The 15 week-parts are not yet collapsed into the hour x day-of-week table.
No modelling.
**Next:** Human's Route A/B/C decision. Then collapse the hour parts, build the modelling
table, run the one-liner benchmark.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — handoff docs + shared ledger built
**Did:** Wrote `00_START_HERE.md` (285 lines) and this `WORKLOG.md`. Added a
"superseded in part" banner to `../00_START_HERE.md` (original backed up to the
session scratchpad) and repointed the `## Final project` section of the workspace
`CLAUDE.md` at this folder. Wrote `notes/outcome_count_reconciliation.md`.
**Found:** Reconciled the two conflicting 311 totals — not a data error, three
defensible filters: 3,738 (de-duped) / 3,629 (coords required) / 3,593 (real community
boards only). **3,629 is the working number.** Also confirmed the ACS income join had
silently failed (259/262 NTAs NA) and got it fixed — root cause was a dplyr scoping
trap, not the ACS sentinel value I had guessed.
**Failed / ruled out:** Nothing attempted failed.
**Left undone:** No modelling. Demand workstream still running at time of writing.
**Next:** Human's Route A/B/C decision, then the one-liner benchmark.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — five research workstreams run from scratch
**Did:** Spawned 5 independent agents (external evidence, 311 outcome, geography,
supply, demand) under an explicit embargo on reading the teammates' folder. Created
this folder and `CONVENTIONS.md`. Produced ~34 files in `data_raw/`, 5 note files,
and the `R/` helper library.
**Found:** (1) **Local Law 58 of 2025 = 2,120 restrooms by 2035** vs 973 today — the
decision hook. (2) A usable outcome variable EXISTS: 311 "Urinating in Public",
3,629 de-duped public-space events. (3) **Top 1% of addresses = 22.6% of complaints**;
naive ranking sends restrooms to the wrong place. (4) **PIP `yg3y-7juh` is a real
natural experiment** — 584 sites switching closed-status, dated 2004-2026, pairs with
173 dated+costed capital projects. (5) A **published method (G2SFCA)** exists, so no
index needs inventing. (6) Cost ladder: new build $3.79M, reconstruction $1.15M,
component work $45k-$76k. (7) Only **9 facilities are 24-hour**.
**Failed / ruled out:** COVID closures `i5n2-q8ck` are NOT a usable natural experiment
(8 close dates, all May-Jun 2020, no control group). `api.census.gov` now rejects all
keyless requests. No rigorous US cost-benefit/WTP study for public toilets exists in
the literature — build benefits as cost-avoidance instead. Parks has no 311 complaint
route for comfort stations, so complaints ABOUT existing restrooms cannot be measured.
**Left undone:** All modelling. Demand lane still running.
**Next:** See the entry above.

### 2026-09-20 — pmba6093-analytics-for-managers-d7 — reviewed inherited proposal, decision to rebuild
**Did:** Ran 4 review agents over the teammates' proposal, the course guidelines, the
datasets, and the archived tree-hazard R code.
**Found:** The proposal's RGI is arithmetic, not analytics — no estimation anywhere,
uses none of the course's taught methods. `SROI = NPV/CapEx` breaks mechanically
(CapEx~0 for hours extension). Its 8-slide plan runs 14:00 against a **12:00 limit**.
The promised `restroom_roi_analysis_template.R` does not exist. **The newer
`Guidelines for the Final Presentation.pdf` supersedes the older `Project_Outline.pdf`**
and explicitly permits an own NYC-sourced topic. Presentation order is first-come via
email to lily959@hku.hk cc weimingz@hku.hk — apparently unclaimed.
**Failed / ruled out:** N/A — review only.
**Left undone:** N/A.
**Next:** Human directed a from-scratch rebuild keeping only the concept.
