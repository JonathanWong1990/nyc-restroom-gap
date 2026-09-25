# Layered diagnosis: the 29 high-complaint NTAs

The layers show where access gaps and excess complaints coincide; they do not show that the gaps cause the complaints. The actions are candidates to verify and test.

Complaints show **where**; three supply layers show **which access gaps coincide** there, which points to a **candidate action** to verify. Run `R/01_layers.R`, `R/03_final_rule.R`, `R/04_maps_final.R`, then `R/05_trial_power.R` (hours trial for the 13 Extend areas: 33% detectable drop; 6 extra hours cost $2.75M Parks / $4.41M all, 10 months). Both reuse the prototype's `prep.rds` and its open-at-hour rule: Wednesday, 500 m straight line, placeholder park hours close at 16:00.

## Layers (`outputs/layers_all197.csv`, 197 residential NTAs)
1. **Problem**: complaints observed ÷ expected. 29 NTAs are at ≥ 1.5. Recomputing A6's empirical-Bayes P(RR>1.5) > 0.95 reproduces the confident six exactly.
2. **Missing**: share of residents with no operational restroom open within 500 m at 2pm.
3. **Closed**: share of residents covered at 2pm but not at 9pm (954 restrooms open at 2pm, 57 at 9pm). **Extendable** is the part of that gap recovered if placeholder park restrooms stayed open until 22:00.
4. **Broken**: Parks restrooms within 500 m of the NTA's residents or inside it. Counts long-term-closed restrooms (PIP) and "repeatedly failing" ones: ≥2 Unacceptable ratings making up ≥50% of A/U inspections since January 2025, with an unambiguous register match within 30 m. **Lost** is the 2pm coverage drop, in percentage points (pp), if those restrooms are removed. Plus the 2026 Jan–Jun PIP failure rate and n.

## Final rule: priority order (fix, build, extend) (`R/03_final_rule.R` → `outputs/diagnosis_29_final.csv`)
Adopted 25 Sep on review. The first rule (`R/01_layers.R`, `outputs/diagnosis_29.csv`: 13 BUILD, 8 FIX, 7 EXTEND, 1 VERIFY) is kept for the record; its FIX clause fired on broken restrooms that other restrooms already back up.
- **FIX**: repairing or reopening restores ≥ 10 pp of resident coverage (lost + reopen gain). A broken restroom that others back up does not qualify.
- **BUILD**: after any fix, Layer 2 ≥ 40% (Tompkinsville sits at about 40%).
- **EXTEND**: Layer 3 ≥ 40% and extendable ≥ half of it.
- **VERIFY**: none of these.

Precedence is FIX > BUILD > EXTEND > VERIFY, with flags kept. Maps: `R/04_maps_final.R`.

**Build split by complaint-signal strength (review A, 25 Sep; in `03_final_rule.R` as `build_signal` / `display_action`):** BUILD areas with empirical-Bayes P(ratio > 1.5) >= 0.75 are "Build" (6: Astoria, East Flatbush, Wakefield, New Dorp, Dyker Heights, Sunset Park; P 0.80-1.00); the rest are "Build, verify first" (6: East Flushing, Port Richmond, Hollis, Breezy Point, St. George, Tompkinsville; P 0.24-0.52; 4-15 complaints). The cut sits in the natural break between 0.52 and 0.80. A daytime gap is common citywide (77 of 197 NTAs), so the build call rests on the complaint signal's strength. The any-location run needs about 7 sites for the six stronger Build candidates (bringing each below 40% uncovered, not to zero) (2 of 6 reach the target on prototype candidates).

**Result: 3 FIX (Brighton Beach, East Harlem (North), Corona), 12 BUILD, 13 EXTEND, 1 VERIFY (Midtown–Times Square).** Brighton Beach stays FIX (26.6 pp) even without the estimated Coney Island Beach restroom locations.

## Sensitivity (`outputs/sensitivity_final.csv`)
- 30% threshold: 1 of 29 changes.
- 50%: 7 change (BUILD falls from 12 to 6).
- 400 m radius: 4 change. The 400 m run changes the missing and closed layers only; the fix gain stays at 500 m.
- 5 pp FIX threshold: 4 change (FIX rises to 7).

## Where to build (`outputs/build_sites.csv`)
Greedy maximal covering of uncovered residents, using candidates inside each BUILD NTA or within 250 m of it. Stops at Layer 2 < 40%, 10 sites, or no gain.

Run on the first rule's 13 BUILD areas. Prototype candidates give 27 sites, all on Parks land; only 4 of 13 reach the target, and 4 have no usable candidate. For the final 12 (Brighton Beach is now FIX): 26 sites, **3 of 12** reach the target.

A diagnostic run that allows any residential grid point reaches the target in all of them with 1–2 sites each (14 sites for the final 12). The candidate inventory limits the current siting result; none of the unrestricted points is verified.

## Pilot (`outputs/pilot_in_29_final.csv`)
3 of 17 pilot sites are inside the 29:
- P11, Astoria (East)-Woodside (North): BUILD
- P12, Woodside: EXTEND
- P17, St. George: BUILD

3 more reach residents of the 29 within 500 m. P04 (Monsignor Raul Del Valle Square) is a long-term-closed restroom near Hunts Point; reopening it adds no coverage because other restrooms reach the same residents, so Hunts Point is EXTEND under the final rule.

## Caveats
Posted hours; register dated June 2025; straight-line distance; grid candidates are not verified sites; the PIP rates rest on 2–18 inspections per NTA; complaints are a screen, not proof of need.
