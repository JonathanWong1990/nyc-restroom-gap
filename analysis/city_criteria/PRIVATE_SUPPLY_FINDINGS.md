> **Updated 26 Sep 2026** after the supply-rule fix (broken restrooms excluded). Current values: `outputs/private_supply_scenarios.csv` (base gap 1,246; 155 existing; 24 new; all-outlets 32/18/2; late-night 266/61/12; 50% access 451/91/14).

# Do chain outlets already fill the gap? (26 Sep 2026, `R/07_private_supply.R`)

**What we tested.** We added 1,854 chain food outlets (DOHMH inspections, 13 chains) as extra supply within 500 m, then re-ran the 05 gap and two-stage cover unchanged. The base case matches 05 exactly (asserted in the script). We dropped 28 rows with no coordinates and 4 that are not the chain.

**How close the chains are.** 1,214 of 1,246 gap sites have a chain outlet within 500 m. 980 have a late-night fast-food outlet (McDonald's, Burger King, Wendy's, Popeyes, KFC, Taco Bell). 21 of the 24 new-unit sites have a chain nearby, 13 of them late-night.

| Scenario | Gap (evening-only / all-day) | Existing (repair / park hrs / other hrs) | New | Base existing not chosen / redundant | Base new areas not needed |
|---|---|---|---|---|---|
| A none | 1,247 (1,182 / 65) | 154 (16/103/35) | 24 | 0 / 0 | 0 |
| B all outlets, 2pm + 9pm | 32 (30 / 2) | 18 (3/15/0) | 2 | 139 / 134 | 22 |
| C late fast food only at 9pm | 268 (266 / 2) | 61 (6/47/8) | 12 | 103 / 76 | 12 |
| C+ C + Chipotle, Shake Shack, Subway | 114 (112 / 2) | 39 (6/29/4) | 8 | 126 / 108 | 16 |
| D C, 50% access: median [range] | 452 [347–564] | 90 [80–100] | 14 [12–18] | 75 [63–86] / 47 [36–59] | 10 [6–12] |

- **Not chosen:** the cover no longer picks that exact restroom.
- **Redundant:** none of the gap sites it served is still a gap.
- **D:** column-wise medians over 200 draws.

**What it means.** On paper, the chains close almost the whole gap. The recommendation therefore depends on whether their toilets count as public, and that is a question about access, not location. Local Law 58 counts public bathrooms. Customer-only toilets with unknown hours are not public (the register already includes privately owned public spaces). Even under generous assumptions (C, D), 12–18 new units and 61–100 existing restrooms are still needed.

**Caveats.**
- There are no observed hours: the late-night list is an assumption.
- We don't know which outlets have a toilet or let non-customers use it.
- Only 13 chains are covered, with no hotels, department stores or independents.
- Some outlets are in airports or stadiums. Distances are straight-line.
