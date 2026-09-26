# Response to REVIEW_FINDINGS.md (26 Sep 2026)

All five findings accepted; owner approved the changes.

1. **Nearby fixes did not preserve coverage.** Fixed by redesign: two-stage covering. Stage 1 selects existing
   restrooms at their own coordinates (repair/reopen, or extend hours to 10pm), deduplicated; stage 2 places new units
   for the remaining gap. The script now checks that every gap site is covered. Result: 154 existing (103 park hours,
   35 other operators, 16 repair) + 24 new units, replacing "156 locations: 101/27/12/16".
2. **Demand scaling.** Fixed: the busyness composite is re-standardised with the fitting data's mean/sd before the
   weights are applied, for baseline, pilots and every sensitivity composite. Gap moved 1,249 -> 1,247.
3. **Interpretation.** Page now says "what the pilot sites have in common" / "model-derived weights"; AUC labelled
   in-sample; leave-one-out described as a held-out ranking check.
4. **Park hours.** Now a two-scenario table (4pm vs 10pm) and step 1 of the recommendation. Under the redesign, park
   hours change the existing restrooms needed (154 vs 29), not the new units (24 in both). Greedy = workable, not minimum.
5. **Stability.** Existing restrooms: exact retention (103/154). New units: labelled area-level within 500 m (13/24).

---

# Response to LOGIC_REVIEW and NUMBERS_SCRIPTS_DATA_AUDIT (26 Sep 2026)

All accepted. Verified independently: all 16 repair picks have 4pm placeholder hours; 34 long-term-closed and 47
repeatedly failing listed restrooms were counted as open at 2pm.
- **Supply rule:** broken restrooms (long-term closed or repeatedly failing) excluded from supply in 01, 05, 06, 07, 08, 09;
  954 / 57 kept only as a register statistic ("scheduled open"). Base now 1,246 gap, 155 existing, 24 new.
- **Repair = repair AND keep open to 10pm**, relabelled everywhere.
- **Pilots:** assumption stated; "none operating" scenario added (1,357 / 162 / 25).
- **24 + residents:** combined run added to 09 (837 total incl. the 24).
- **830:** now "about 830 in this scenario", not a floor or minimum; greedy caveat stated.
- **Existing restrooms:** described as a list to verify (hours, operator agreement, access, repair scope, cost).
- **Wording:** "answer key" -> reference; "solves" -> "based on"; gap sites are points, not people.
- **Reproducibility:** prep.rds (3.5 MB) added to the repository.
