> **Archived long-form write-up.** The live version of this project is the site —
> Walkthrough, Limits, and Data & code:
> https://jonathanwong1990.github.io/nyc-restroom-gap/
> This file is the prose report it was built from, kept for reference only. If a
> number here disagrees with the site, **the site is right** — check it before quoting
> anything from this file.

# When nature calls, where should New York answer?

*PMBA6093 · Analytics for Managers · Final project*

New York City has committed to having 2,120 public restrooms by 2035. It has 973 in operation. It has no published method for deciding where the next ones go. This is an attempt at such a method, and an account of what the data says once you build one.

**Analysis covers 197 neighbourhoods and six models. Data current to September 2026.**

---

## The takeaway in one screen

Three findings, in the order that matters.

**A public restroom is a service, and it costs about $2.25 per use.** A median facility costs $2,331,000, or $164,012 a year across a twenty-year life, against roughly 73,000 visits. That is ordinary municipal infrastructure pricing. Complaints are used here to find where demand goes unmet, not to price the building.

**Four in five public restrooms are in parks; the demand is on streets.** Of the 1,066 facilities in our September 2026 extract, 824 sit inside parks. (The Council's December 2025 report counts 1,063 and 821; the dataset refreshes about twice a year.) Complaints concentrate at transit interchanges, commercial strips and nightlife districts. Three separate tests point the same way, and the mechanism is prosaic: restroom money flows through Parks Department capital projects, and Parks capital projects reach parks.

**The data supports an ordering of neighbourhoods, not a verdict on any one of them.** With roughly fifteen complaints per neighbourhood over six years, a ranking is the most the record will carry. That shapes the recommendation: start with a cheap experiment that measures what a restroom actually does, then build on the answer.

| | |
|---|---|
| **2,120** | Target restrooms by 2035 (Local Law 58) |
| **8** | Facilities open 24 hours, citywide |
| **37%** | Subway complexes with no restroom within 400m |
| **3** | Comfort stations' worth of capital covers 27 areas |

Figures are derived from NYC Open Data, MTA, TLC and US Census sources, and reproduced from raw data rather than quoted from secondary reports.

---

## 1. The question New York has to answer

Local Law 58 of 2025 is a planning mandate. It requires a Deputy Mayor to lead a citywide bathroom strategy and to file a strategic planning report, updated every four years, working toward a target metric of at least 2,120 public bathrooms by 2035, at least half publicly owned. Nothing in the law obliges the city to build a single facility.

What the law does oblige the city to produce is a method: a capital strategy, a set of conversion sites, a modular design recommendation, and a public map. Against 973 operational restrooms today, the target implies roughly 1,150 additional facilities. That is a planning shortfall the city has to explain how it will close, and the explanation is due.

Money is not the obvious constraint. Between 2006 and today, the city's Automatic Public Toilet programme promised twenty units. Five were installed. Fifteen sat in a Queens warehouse for more than a decade. The hardware had been bought; the city could not decide where to put it.

The audience for a siting method is specific. The Mayor's Office of Operations owns the strategy. NYC Parks decides what to reopen or extend. DOT Public Realm sites units in plazas. The MTA knows which station complexes have weak access. Each of those bodies can make a different decision, and a useful analysis has to say which decision it is informing.

---

A median restroom project costs $2,331,000, or $164,012 a year across a twenty-year life. Against roughly 73,000 visits a year that is about $2.25 a use — ordinary municipal infrastructure pricing.

| | |
|---|---|
| **$2.25** | Cost per use at 200 visits a day |
| **$1.12** | Cost per use at 400 visits a day |
| **$2.67bn** | Capital implied by the 2035 target |
| **$315** | That target, per New Yorker |



## 2. The complaint record

### The data

Every dataset below was pulled and verified directly from its source. Join keys were checked for cardinality before any aggregation, and the failures were recorded as findings.

| Source | What it gives | Scale | Verdict |
|---|---|---|---|
| 311 Service Requests | Public-urination complaints — the outcome | 3,629 | core |
| MTA subway ridership | Transit presence by station | 426 complexes | strong |
| LEHD workplace jobs | Where people work, not sleep | 4.59M jobs | strong |
| NYC Public Restrooms | Supply, hours, accessibility | 1,066* | core |
| Parks capital projects | Real construction costs | 191 restroom | strong |
| Park inspections (PIP) | 20 years of facility condition | 31,768 | strong |
| Hotels (tax records) | Tourist presence proxy | 1,225 | moderate |
| US Census ACS | Population, income, age, disability | 2,325 tracts | core |

\* Our September 2026 pull returns 1,066 records; the Council's December 2025 report states 1,063 and its dashboard 1,064. The dataset refreshes roughly twice yearly. All sources pulled September 2026. Hosts differ: MTA data is on data.ny.gov, not NYC Open Data.

Taxi activity is marked as tested because it was. Added to the model it is not statistically significant (rate ratio 1.096, p = 0.39) and it leaves the ranking unchanged, so it is not carried in the published specification.


### The concentration problem inside 311

Complaints stand in for unmet need, and they are a noisy stand-in. The decisive difficulty is not general reporting bias. It is a small number of addresses.

The top 1% of addresses generate 22.6% of all complaints. Ranked on raw counts, East Harlem is the worst place in New York — but 223 of its 384 complaints come from five adjacent addresses on East 122nd Street. The Rockaways rank second, with 286 of 327 complaints coming from three addresses on Bayport Place.

Raw 311 data, in other words, does not rank where restrooms are missing. It ranks where one persistent complainant lives next to one nuisance site. De-duplicating to one count per address per month costs 20.8% of records and produces a completely different answer. The top ten becomes Midtown, the Upper West Side, Chelsea, the Village, the Financial District, the Upper East Side, Elmhurst, Jackson Heights, Astoria and Downtown Brooklyn — high-footfall commercial and transit districts, which at least has face validity. Every complaint figure in this analysis uses the de-duplicated series.

One bias survives de-duplication. Complaint volume correlates 0.597 with the share of complaints filed online, so app-using neighbourhoods over-report, and that tilts any investment case toward Manhattan. Section 8 reports what happens when the analysis is restricted to phone-filed complaints; the result is not clean. A cruder worry, that some neighbourhoods simply complain about everything more, turns out not to bind: correlation with total 311 volume across all complaint types is 0.027.

Two further properties of the series matter for interpretation. Complaint timestamps are report times, not incident times. And the person who files a complaint and the person who needed a toilet are different people with opposed interests, which is a limitation of the outcome variable that no amount of cleaning removes.

---

## 3. The evening gap

Street urination in this data is not mainly a late-night phenomenon. It peaks at exactly the hour the restrooms shut.

| Window | Share of complaints | Share of facilities open |
|---|---|---|
| 12:00–17:59 afternoon | 36.9% | 81–86% |
| 18:00–23:59 evening | 29.9% | 45% → 7% |
| 00:00–05:59 overnight | 5.7% | under 3% |

The busiest single hour for complaints is 18:00, which is the hour at which availability falls off a cliff. Among facilities with genuine recorded hours, 86% are open at 15:00, 45% at 18:00, 15% at 21:00 and 7% at 23:00. Roughly a third of complaints arrive in a window when most of the network has closed. Eight facilities citywide operate 24 hours; that count matches the Council's own figure exactly and was derived here independently from the raw records.

Availability above is computed from only 318 facilities, because those are the ones whose hours are genuinely recorded. Of the 843 in the relevant set, 525 carry the identical placeholder string "8am-4pm, Open later seasonally" — Parks Department boilerplate that records nothing about when anything opens. Every figure in this section excludes them.

That exclusion is worth sitting with for a moment, because it is a finding of its own: the city cannot currently answer the question "what is open at 9pm?" from its own asset register.

---

One consequence is worth stating on its own. Because 525 of 843 hours records carry identical Parks Department placeholder text, the city cannot currently answer "what is open at 9pm?" from its own asset register. Any siting strategy that proposes to manage opening hours has to fix that record first.

## 4. Where the restrooms are, and where the demand is

The hypothesis is that New York's restroom stock does not address the demand that generates street urination, because the stock is park-based and the demand is street-based. Three tests bear on it. Two produce usable evidence and one does not.

### Supply against need

Across neighbourhoods, places with more restrooms have *more* complaints, with a correlation of +0.304. Taken at face value that would recommend demolishing restrooms. It is confounding: the city builds where crowds already are, and crowds produce both restrooms and complaints.

To separate those, we fit a negative binomial regression of complaints on subway ridership, jobs, hotels, restroom count, density, income, poverty, age and borough, with a population offset. A negative binomial model is a standard tool for count outcomes that vary more than a simple Poisson model allows; the population offset means the model predicts complaints per resident rather than raw totals. Coefficients are reported as rate ratios, where 1.000 means no relationship and 1.063 means a one-unit increase raises the expected count by 6.3%.

Restroom count comes out at a rate ratio of 1.001, with p = 0.99. This is uninformative rather than a proven zero. Existing supply was placed where demand already is, so the coefficient cannot be read as the effect of adding a restroom. What it does say is that current supply neither helps nor hurts once you account for who is present.

The other coefficients behave sensibly. Subway ridership and jobs both predict complaints (rate ratio 1.063, p < 0.001, and p = 0.042 respectively). The share of residents over 65 is associated with fewer complaints (0.964, p = 0.002). Hotels come in at 1.124 but do not survive clustered standard errors (p = 0.100), so we make no claim about them.

### Where does the capital actually go?

Of the 197 residential neighbourhoods modelled, **105 received a Parks capital restroom project**. (Across all 262 NTAs, 126 did — the extra 21 are places like Crotona Park and Lincoln Terrace Park, which are parks rather than neighbourhoods and sit outside the residential set. That is a small piece of evidence for the finding below.) A logistic regression — a model for yes/no outcomes, reporting odds ratios where 1.0 means no effect — predicts which ones.

| Predictor | Odds ratio | 95% CI | p | Reading |
|---|---|---|---|---|
| Poverty (per +10 points) | 2.19 | — | 0.0006 | predicts |
| Parkland (per doubling of acreage) | 1.49 | 1.12–1.99 | 0.0058 | predicts |
| Measured unmet need | 1.60 | 0.95–2.69 | 0.078 | **not significant** |
| Subway ridership | 1.08 | 0.98–1.19 | 0.122 | not significant |

*Logistic regression, n = 197. Out-of-sample over 200 splits: accuracy 0.610, precision 0.637, recall 0.631, against a 0.533 majority-class baseline.*

Parkland and poverty are estimated precisely. Need is not: its interval runs from 0.95 to 2.69, so the data are consistent with need mattering substantially and equally consistent with it mattering not at all. **We cannot claim the city is blind to need** — only that this record does not show it responding to need.

Three qualifications. Seventy-six percent of these projects began design before 2020, so they could not have responded to complaints filed between 2020 and 2026. "Need" here is itself a model residual, which makes its stated p-value optimistic. And p = 0.078 is **not** a result: it is a non-finding that happens to sit near a conventional threshold, and should not be read as significance at the 10% level.

One result cuts against the easy narrative. Poverty roughly doubles the odds of investment per ten points. New York is spending in poorer neighbourhoods, so this is not a story about class. It is a story about the category of place the funding pipeline can reach.

## 5. Ranking neighbourhoods by unexplained need

The ranking model is a negative binomial regression across 197 residential neighbourhoods, with a population offset, borough dummy variables, and standard errors clustered by community district (59 clusters). Validation is out-of-sample: the model is fit on a random 70% of neighbourhoods and scored on the held-out 30%, repeated 200 times. Results are stable across six random seeds (0.786–0.795).

| Model | Out-of-sample rank correlation |
|---|---|
| Negative binomial | 0.793 |
| Decision tree | 0.720 |
| Tree (pruned) | 0.713 |
| Benchmark: subway ridership only | 0.709 |

*Mean of 200 random 70/30 splits, scored against held-out data.*

The regression beats the benchmark in 94% of splits (92–98% across seeds). We fit a decision tree as well, expecting it to lose, since a tree with 197 observations will overfit, and it did lose — the regression beats it in 94% of splits. To be fair to the tree, its mean score of 0.720 does edge the benchmark's 0.709; it loses on win-rate, not on average.

### The residual is the useful output

The prediction itself is not what a siting decision needs. What it needs is the **residual**: the gap between how many complaints a neighbourhood actually generates and how many its transit, employment, hotel and demographic profile predict. A neighbourhood generating three times its predicted complaints has demand that its characteristics do not explain, which is the closest observable thing to unmet need.

Define the unmet-need ratio as observed complaints divided by model prediction. Coverage is the share of a neighbourhood's land within a five-minute walk of an operational restroom.

| Neighbourhood | Observed | Predicted | Ratio | Restrooms | Coverage |
|---|---|---|---|---|---|
| Brighton Beach | 24 | 6.3 | 3.82× | 1 | 38% |
| East Elmhurst | 36 | 10.1 | 3.57× | 5 | 67% |
| East Flatbush–Rugby | 18 | 5.7 | 3.18× | 3 | 33% |
| East Harlem (North) | 99 | 33.2 | 2.98× | 6 | 78% |
| Williamsbridge–Olinville | 39 | 13.3 | 2.94× | 5 | 63% |
| Astoria (East)–Woodside (N) | 57 | 20.5 | 2.78× | 2 | 34% |

These are outer-borough, low-supply, largely non-touristy places. Neither a hand-weighted index nor the simple ridership benchmark would have surfaced any of them. Ranking on raw complaints points at Midtown, which is already the best-served part of the city.

Ratio and absolute deficit answer different questions, and a build decision needs both. Ranked by absolute excess complaints, the order changes: East Harlem (North) +66, Midtown–Times Square +40, Astoria (E)–Woodside (N) +36, West Village +26, East Elmhurst +26. Brighton Beach tops the ratio and does not appear in the top ten by volume. The ratio identifies the most underserved place per unit of demand; the excess identifies the biggest absolute deficit.

**Map of unmet need.** The full ranking is mapped across all 197 residential neighbourhoods, shaded by the ratio of observed complaints to model prediction, in bands: under 0.6 · 0.6–0.9 · 0.9–1.2 · 1.2–1.6 · 1.6–2.2 · over 2.2. Darker shading means more unmet need than the area's transit, employment, hotel and demographic profile predicts. The Financial District and the Upper West Side sit pale despite high raw complaint counts, because their volume is fully explained by how many people are there. Every neighbourhood's figures appear in Appendix A.

### Setting a bar first

Before building anything, we set a bar that any model would have to clear: a rule simple enough to write in one line. Ranking neighbourhoods by subway ridership alone predicts complaints with a rank correlation of 0.709. A more targeted rule — ridership at stations with no restroom within 400 metres — scores 0.487 on the same basis. The obvious refinement makes the prediction worse, which is the reason to set a bar before building anything. Rank correlation measures how well one ordering reproduces another, on a scale where 1.0 is a perfect match. That single variable, with no model behind it, is a strong benchmark. ---

A ranking built on roughly fifteen events per neighbourhood invites one question above all others. Four tests bear on it, and the first is the one that constrains everything else.

### Signal against noise

The model estimates an expected count for each neighbourhood and how much counts naturally scatter around it. That makes a direct test possible — but the test depends entirely on what "no unmet need" is taken to mean, and there are two defensible versions.

A negative binomial is a Poisson process whose rate varies between places. Its overdispersion parameter measures exactly that variation, here ±47%. So simulating from the fitted model does **not** produce a world where nothing is wrong; it produces one where places differ by precisely the amount we measured. Both nulls are informative, and they answer different questions.

| Quantity | Poisson null (places do **not** differ) | NB null (places **do** differ) | Observed |
|---|---|---|---|
| Neighbourhoods scoring 1.5× or above | 11.9 (95% range 7–18) | 33.8 (95% range 27–41) | **29** |
| Highest single ratio | 2.25 (95th pct 2.93) | 3.07 (95th pct 3.92) | **3.82** |
| p(simulated max ≥ observed) | **0.002** | 0.068 | — |

Against the Poisson null, the spread is far beyond luck: real variation exists, about two and a half times what chance produces. Against the NB null, the *count* of extreme places is roughly what the estimated spread predicts — so the extremes are the top of a continuum, not a distinct category of broken neighbourhoods. The 1.5× threshold is therefore a budget line, not a boundary the data marks.

For an individual neighbourhood, the relevant quantity is a posterior rather than a bootstrap. Reading the same fitted model as the Poisson-gamma model it already is gives **seven neighbourhoods above 95% posterior probability** that their true rate exceeds 1.5× expected: East Harlem (North), Astoria (East)–Woodside (North), East Elmhurst, Williamsbridge–Olinville, Brighton Beach, Midtown–Times Square and East Flatbush–Rugby. All seven survive leave-one-out re-estimation of both the model and the prior.

Correcting for testing all 197 places simultaneously, none is a "discovery" in the family-wise sense. That is not a contradiction — multiple-testing correction screens hypotheses, posteriors allocate budgets — but it bounds the claim. The defensible statement is about where to look and where to spend, not about having proven a fact regarding any one place. And all of it addresses thin counts only; none of it touches what the counts measure.

### Sensitivity to who reports

Restricting the outcome to phone-filed complaints only — 36.8% of records, and the channel least affected by app-adoption bias — moves three of the top six sharply.

| Neighbourhood | Rank, all complaints | Rank, phone-filed only |
|---|---|---|
| East Flatbush–Rugby | 3 | 1 |
| Brighton Beach | 1 | 2 |
| East Elmhurst | 2 | 5 |
| East Harlem (North) | 4 | 41 |
| Williamsbridge–Olinville | 5 | 52 |
| Astoria (E)–Woodside (N) | 6 | 123 |

Top-ten overlap between the two rankings is 4 of 10. East Flatbush–Rugby, Brighton Beach and East Elmhurst hold up under the change of reporting channel; the other three depend on who files. Given the noise-floor result above, the accurate description of all six is that they sit at the top of the best available ordering.

One detail hints at why a reasonably well-supplied area can still show high unmet need. Of East Elmhurst's five operational restrooms, one is fully accessible. That is 20%, against 59% citywide. Supply counted at the door is not supply available to everyone.

---

The ranking cannot single out neighbourhoods, and it is not offered as though it could. What it provides is an ordering: if the city has to place facilities somewhere, these areas are a better starting point than a list assembled by hand or by raw complaint count. That is a weaker claim than a shortlist of proven need, and it is the claim the evidence supports.

## 6. What the fixes would cost

The ranking supports an ordering rather than a verdict, and the costing inherits that. What follows prices a set of candidate areas; it does not assert that each one is proven to need the money. None of it is a return-on-investment calculation, and there is no honest way to produce one — the figures below are what the options cost, not what they are worth.

Costing runs only on the shortlist of 29 neighbourhoods at an unmet-need ratio of 1.5 or above, and never citywide. This matters because pricing an intervention everywhere invites the model to spend money in places the evidence never identified.

The cause of the gap differs by place, and so does the appropriate fix.

- **Brighton Beach** — 38% coverage, one restroom. The facility genuinely is not there. Build.
- **East Harlem (North)** — 78% coverage, six restrooms, and still three times the predicted complaints. The buildings exist. The constraint is hours, capacity or condition.

### What a restroom costs

Costs come from NYC's own capital tracker: 191 restroom projects, with a median project cost of **$2,331,000**.

Reaching that median requires a decision about incomplete records. Of the 191 projects, 128 state an exact figure and 63 are given as cost bands. Those bands are overwhelmingly the expensive projects: 90% of them are $3M or more, against 28% of the exact-figure projects. Dropping them therefore produces the median of the cheap half, which is $1,559,000. Valuing each band at its lower bound — the most conservative available choice — gives $2,331,000, and valuing them at band midpoints gives the same figure. The median used throughout this analysis is $2,331,000.

### How the options are compared

Every option is annualised before comparison: modular construction over 20 years, repairs over 10, at a 3.5% discount rate throughout. Extended opening hours are priced as incremental staffing.

Annualising is what makes the comparison meaningful. Price extended hours at zero capital cost and cost-per-complaint comes out at zero, so hours extension wins everywhere mechanically, whatever the data says. Any decision rule of the form "net present value divided by capital cost" has this defect built in, because the denominator goes to zero for the cheapest intervention.

One input cannot be sourced. The only NYC operating-cost figure available is Bryant Park at $271,000 a year, which as noted is an attended, premium, flower-bedecked facility and not a citywide baseline. Staffing is therefore an explicit assumption: **$35 per hour, four added hours per day**.

The precise wage does not move the ranking, for a structural reason worth stating: hours extension stops being the cheapest option only at $4.86 per hour. Above roughly $5 an hour the ranking is wage-invariant, and we did not test below that. What genuinely moves the programme total is the intervention thresholds — the rules determining when a neighbourhood gets construction rather than hours. Across a 27-combination grid of those thresholds, programme cost ranges from $0.95M to $1.64M.

### Which fix goes where

Each shortlisted area is assigned the cheapest intervention its own conditions allow, by a rule applied in order:

| Condition | Assigned intervention |
|---|---|
| No operational restroom, or under 35% of the area within a five-minute walk | Build, or install a modular unit |
| Facilities present but a fifth or more rated unacceptable at inspection | Reconstruct or repair |
| Facilities present and in condition, but closing before 9pm | Extend opening hours |
| None of the above | Already served |

The thresholds are judgement calls, and the mix is sensitive to them: across a grid of twenty-seven plausible combinations the programme cost ranges from $0.95M to $1.64M. The ordering of the rule matters more than any single threshold.

### The programme

| | |
|---|---|
| **29** | Priority neighbourhoods |
| **10** | Where the cheapest option is hours, not construction |
| **$11.3M** | Capital for all 27 costable areas |
| **~3** | Comfort stations that capital would otherwise buy |

Roughly three comfort stations' worth of capital, plus about $0.5M a year to run, reaches twenty-seven neighbourhoods instead of one site.

Two cautions on reading those numbers. The comparison that holds is capital against capital: $11.3M against the capital cost of roughly three traditional comfort stations. On an annualised basis one traditional comfort station is roughly $250,000 a year, and the programme is roughly five times that — a recurring cost and a one-off capital cost are different quantities and comparing them across categories produces nonsense. Separately, NYC capital and expense budgets are not fungible. The $11.3M and the $0.5M a year are two different asks of two different budget lines.

---

## 7. Limits of the evidence

These limits shape what the recommendation in the next section can carry.

**Restrooms have not been shown to reduce street urination.** Two causal designs were built and both were abandoned: the first for insufficient power, since it could only have detected effects larger than about ±20%, and the second because it failed its own placebo test. A failed design yields no evidence in either direction, which is different from evidence of no effect.

**Complaints are not need.** They are a reported proxy, biased toward neighbourhoods that report online. The worst distortion is de-duplicated away; the remainder is disclosed and tested in section 8.

**The whole ranking rests on one thin, biased instrument** — about fifteen complaints per neighbourhood over six years. A denser alternative measure exists in the form of police summonses, and we rejected it because it measures policing activity rather than need. That leaves the weaker measure, chosen deliberately.

**Closure dates are imprecise.** Park inspections occur about 1.9 times a year, so treatment timing is known only to within roughly six months. Facilities also switch status repeatedly rather than once, which standard difference-in-differences methods handle badly.

**The restroom inventory is 15 months stale.** The catalogue claims November 2025; the underlying rows were last updated 27 June 2025.

**No benefit valuation exists.** There is no rigorous US cost-benefit or willingness-to-pay study for public toilets, so this analysis reports cost-effectiveness per excess complaint and declines to invent a welfare figure.

**Cost-effectiveness figures are per six years, not per year.** Complaint counts span 2 January 2020 to 18 September 2026, a period of 6.71 years. Any cost-per-complaint figure must divide the excess by 6.71 to be annual.

**Commercial supply is only partially measured.** We mapped 1,886 chain locations — Dunkin, Starbucks, McDonald's and ten others — from city inspection records, on the theory that informal supply might substitute for public provision. It shows no association with unmet need (IRR 1.075, p = 0.39), and adding it leaves the ranking essentially identical (rank correlation 0.997, top ten unchanged). Thirteen chains is not the whole market, and presence is not permission.

**The parks thesis is inferred, not measured.** Section 4 sets out what supports it and what does not.

---

## 8. What we would do first

The analysis ends in a decision. Because nobody can currently measure whether provision works, the first move is designed to find out.

**Run a staggered trial of extended hours.** Ten of the 29 priority neighbourhoods need no construction. These are the places where §3's evening gap is the binding constraint — facilities exist and are in reasonable condition, but close before the hour complaints peak, only longer opening. Extend closing time by four hours at those facilities in randomised order over ten months. Every neighbourhood is treated by the end, so nothing is withheld from anyone; the staggering is what makes the effect measurable, because at any given month some facilities have been extended and some have not.

- **Outcome measured:** phone-filed public-urination complaints within 400m, phone-only because that is the channel-robust series.
- **Cost:** about $51,000 a year per facility in staffing, and no capital.
- **What it produces:** the first credible estimate of what a restroom-hour is worth in New York — the number this literature is missing, and the number the observational designs here could not supply.

**Then spend the $11.3M of capital on the build sites**, informed by a measured effect instead of an assumed one. East Flatbush–Rugby, Brighton Beach and East Elmhurst are where we would start, being the three that hold up under every robustness test. East Harlem (North) and Midtown–Times Square are the largest absolute deficits.


---

## Dead ends and cautions

Things that did not work, and things worth knowing before anyone repeats them. None of this belongs in a twelve-minute talk; all of it is worth ten minutes of a teammate's time.

### Failed: measuring whether a toilet actually works

**Attempt 1 — park closure records.**
- Idea: find toilets that closed, see whether nearby complaints rose.
- Killed by the data: the field we used records *construction activity*, not closure. Only **151 of 2,057** flagged records actually read "Closed".
- Corrected, it rests on 44 facilities and could only have detected an effect larger than **±20%**.

**Attempt 2 — winter closures.**
- Idea: about **132** toilets shut every winter and reopen in spring, while **843** stay open. A natural before-and-after with a built-in control group.
- It produced a clean-looking result: closure associated with **38% fewer** nearby summonses.
- Killed by its own control test: **alcohol summonses moved almost as much** (rate ratio 0.699 against 0.624). Alcohol has nothing to do with toilets.
- Why: seasonal toilets sit in parks, and parks empty in winter. Every kind of street summons falls together. The effect was the season, not the toilet.
- **This is why we publish no effect estimate.** A design that fails its own placebo gives no evidence in either direction.

### Rejected: a denser outcome measure

- **NYPD public-urination summonses**: 27,384 records, cleanly coded, fully geocoded — against roughly 2,000 complaints over the same window. Looked like a clear upgrade.
- Rejected because they measure **policing, not need**. Correlation with alcohol-possession summonses across neighbourhoods: **0.95**.
- Tested against the right benchmark — enforcement intensity rather than subway ridership — a demand model **wins in 3% of trials**.
- A ranking built on summonses would be a map of where police patrol.
- **Still useful for two things**: enforcement contaminates levels but not changes, so summonses remain the right outcome for a before-and-after design; and the alcohol series makes a ready-made placebo, which is what exposed the winterization result above.

### Rejected: datasets that looked useful

- **Cultural organisations** (2,535 records) — widely used as a tourist-attraction measure. It is a grants roster: 429 theatre companies, 403 music organisations, **99 museums**. A thirty-seat Bushwick collective and the Metropolitan Museum each occupy one row. Omits Times Square, the High Line and Central Park entirely.
- **DOT pedestrian counts** — 114 screenlines for the whole city. Too sparse to model on, though a genuine nineteen-year series where it does cover.
- **Taxi and rideshare activity** — added to the model it is not significant (p = 0.39) and leaves the ranking unchanged.

### Tested and survived

- **Commercial supply.** 1,886 chain coffee shops and fast-food outlets, on the theory that a Starbucks is a toilet in practice. No association with unmet need (p = 0.39); ranking essentially unchanged (rank correlation 0.997).
- **Exposure measure.** Dividing by residents rather than by daytime population could have manufactured the outer-borough result. Refitted three ways, the same names appear (correlations 0.92, 0.98, 0.997).
- **Spatial clustering.** If unexplained need clumped geographically, the shortlist could be one area counted several times. Moran's I = 0.107, p = 0.21 — no clustering.
- **Random seeds.** Out-of-sample score lands between 0.786 and 0.795 across six seeds.
- **A machine-learning comparison.** A decision tree scores 0.720 against the regression's 0.793 and beats the crude benchmark only 55% of the time. With 197 observations it overfits, as expected.

### Cautions for anyone using this data

- **Two-thirds of opening-hours records are placeholder text.** 525 of 843 facilities carry the identical string "8am-4pm, Open later seasonally". Every hours figure here excludes them. It also means the city cannot answer "what is open at 9pm?" from its own asset register.
- **The restroom inventory is 15 months stale.** The catalogue claims November 2025; the underlying rows were last updated 27 June 2025.
- **Three 311 complaint types were retired in 2021** and return zero rows silently — a naive query looks like a clean null result.
- **The capital tracker's 247 rows are 191 projects.** Bundled projects repeat costs; summing raw rows overstates spend 2.4×. A third of projects give costs only as bands, and those bands are the expensive ones.
- **Two figures in wide circulation should not be used.** The "49.42% of residents within a five-minute walk" appears only on a dashboard with no published method. The "93rd of 100 US cities" ranking is real but counts park bathrooms in a 2019 self-reported survey.

### Why there is no return-on-investment figure

- No rigorous US cost-benefit or willingness-to-pay study for public toilets exists. We searched twice.
- Inverting the question — how large would the benefit have to be? — gives a hurdle of **164 avoided incidents a year**, about three a week, at an assumed $1,000 each.
- Three a week is a low bar for a busy site. Proving it is the problem: the city logs only about ten public-urination complaints a week in total, so three avoided events at one location cannot be detected in that record.
- For scale: the San Francisco study implies roughly 50 avoided reports per facility per year. Applied to New York's ~970 facilities that would be 48,650 — ninety times the city's entire annual complaint count. The transfer fails.

## Open questions for the team

Decisions taken in the analysis that the group has not signed off, and questions that need answering before this goes further. Every known weakness is in **What's wrong with it** — this tab is only what needs deciding.

**How to present the null result.** Two causal designs were built and both abandoned; the second failed a placebo test set for it in advance. This is the single most important thing to align on, because it shapes the whole presentation. Two defensible framings, and the group should pick one deliberately. Lead with it: *"nobody in New York can currently measure whether a public restroom does anything — here is why, and here is the experiment that would settle it."* Confident, unusual, hard to attack. Or bury it in limitations, which is safer right up until a sharp examiner finds it in Q&A, at which point it looks like something we hoped they would miss. My recommendation is the first, and it is also why the final ask is a pilot rather than a construction plan.

**Three names or six.** East Flatbush–Rugby, Brighton Beach and East Elmhurst survive every test. East Harlem (North), Williamsbridge–Olinville and Astoria (East)–Woodside (North) are model-supported but reporting-sensitive. Present three with high confidence, or six with a stated caveat?

**Presentation mechanics.** Twelve minutes, six to eight people. The analysis is currently single-threaded through one person, which is a delivery risk. Twelve sections and six models will not fit in twelve minutes, and the danger in compressing is that the caveats go first — which is exactly where the credibility lives.

**What happened to the original index.** The group's earlier proposal scored neighbourhoods with a weighted index whose weights were chosen by hand. This analysis estimates them from data instead, because assigned weights cannot answer the obvious question: move one weight from 0.35 to 0.30 and does the top ten change? What that costs is a tidy slide and an easy explanation. What it buys is coefficients with standard errors and a defence in Q&A. Two things from the original proposal are kept and worth keeping: costing interventions only for a verified shortlist, and mapping each decision-maker to the decision they actually control. If someone wants to defend the original index, a fair hearing beats a quiet replacement.

**Course methods covered** — checked against the delivered decks, not the printed syllabus, because the two differ. Regression (Session 4); dummy variables and spatial analysis (**Session 5** — its agenda slide reads "Dummy Variables · Spatial Data"); logistic regression and confusion matrix (Session 6); trees and train/test (Session 7); difference-in-differences, natural experiments and matching (**Session 8** — DiD and panel data were moved here from Session 5, and the Session 5 deck shows the schedule being corrected); staggered trial design (Session 9, not yet taught). **Regression discontinuity was never taught** — it appears in the printed syllabus and in none of the seven decks — so it is correctly absent. Still uncovered and cheap: propensity score matching (Session 8), and kNN (Session 7), which earlier notes wrongly called inapplicable.

**Questions for the professor.** Is *"where should the next 1,150 restrooms go, and which need building at all"* the right question for this audience? Is it acceptable to lead with a null causal result as supporting evidence? Does the method mix sit at the right level? And is it acceptable that the strongest recommendation is an experiment to run rather than a site to build, given the effect could not be measured from observational data?

---

## Appendix: Sources and reproduction

Independent analysis built from primary sources: NYC Open Data, data.ny.gov, US Census ACS and LEHD.

**Outcome variable:** 311 public-urination complaints, 2 January 2020 to 18 September 2026 (6.71 years), de-duplicated to one record per address-month. 3,629 citywide, of which 3,556 fall within the 197 residential neighbourhood tabulation areas modelled. Citywide that is roughly 540 complaints a year; within the modelled areas, roughly 530.

Everything behind this analysis is published: all 35 scripts, 7 research notes, 60 datasets, reproduction instructions, and interactive maps of unmet need and of the coverage gap.

- Repository: https://github.com/JonathanWong1990/nyc-restroom-gap
- Methods: https://github.com/JonathanWong1990/nyc-restroom-gap/blob/main/METHODS.md
- Interactive map, unmet need: `maps/unmet-need.html`
- Interactive map, coverage gap: `maps/coverage-gap.html`
