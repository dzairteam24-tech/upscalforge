# Animation Director: rejection checklist

Answer each question yes or no. Any "yes" rejects the item. Quote the offending shot ID and cell in the verdict. This list can only reject; passing it does not prove quality.

Source labels: `[F#]` refers to a finding in the master library's `research/animation-director.md`; `[proposal]` means no opened source supports it yet.

| # | Reject if yes | Fail example | Pass example | Source |
|---|---|---|---|---|
| 1 | Is the Purpose cell empty, or a restatement of the action? | `S02-03 Purpose: Mara walks in` | `S02-03 Purpose: Reveals — Mara is limping, so the fall was real` | [F1] |
| 2 | Does the shot map to exactly one screenplay sentence, for three or more shots in a row? | Three rows, each copying one action line | Two action lines covered by one wide; a third split into look + object | [F2] |
| 3 | Is the same size and angle used three times in a row with no stated reason? | `MS eye-level` ×3 | `MS, MS, CU (she notices the key)` | [proposal] |
| 4 | Does the Movement cell name a move with no motivation? | `slow push in` | `slow push in: he understands he is alone` | [F4] |
| 5 | Is the Acting cell an emotion label? | `sad` | `stops stirring; spoon stays in the cup` | [proposal] |
| 6 | Does a shot re-describe a character, location, or prop instead of citing its ID? | `a tall woman in a red coat enters` | `C01 enters (wardrobe S04)` | [F3] |
| 7 | Does a canonical prompt block differ in wording between two places? | Bible: `grey wool coat`; notes: `gray jacket` | Identical block pasted in both | [F3] |
| 8 | Is there an establishing shot of a location already established and unchanged? | Second exterior of the same house, same time | Exterior only when the storm has arrived | [proposal] |
| 9 | Do two consecutive shots give the audience the same information from different angles? | CU letter, then OTS of the same letter | CU letter, then her hand closing over it | [F2] |
| 10 | Does the action in a shot need more motion than the production method handles reliably, with no risk flag? | AI video: `C01 runs, jumps, turns, catches` in one shot | Split into three shots, or flagged `risk: complex motion` | [F5] |
| 11 | Does a reaction shot show no change in the character? | `C02 listens` | `C02's smile fades as the name is said` | [proposal] |
| 12 | Do shot durations miss the target runtime by more than 5 percent? | Target 60 s, total 74 s | Target 60 s, total 61 s | [proposal] |
| 13 | Does a shot change story facts from the approved screenplay? | Adds a character not in the scene | Flags the gap under "Returned to Writer" | [proposal] |

Verdict format:

```
REJECT #4 — S05-02 Movement: "orbit around C01" — no motivation stated.
```
