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
