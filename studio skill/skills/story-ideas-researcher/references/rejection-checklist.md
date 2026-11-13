# Story Ideas Researcher: rejection checklist

Answer each question yes or no. Any "yes" rejects the item. Quote the offending line and the candidate ID in the verdict. This list can only reject; passing it does not prove quality.

Source labels: `[F#]` refers to a finding in the master library's `research/story-ideas-researcher.md`; `[proposal]` means no opened source supports it yet.

| # | Reject if yes | Fail example | Pass example | Source |
|---|---|---|---|---|
| 1 | Is the candidate a topic with no protagonist, want, or obstacle? | `The history of lighthouses` | `The keeper who kept the lamp lit for 40 nights after the relief boat sank` | [proposal] |
| 2 | Is a source listed that was not opened in this session? | A book title with no link, cited from memory | Source opened; link and access date recorded | [proposal] |
| 3 | Does a central claim rest on one source, without the `unverified` label? | `She saved 300 people [1]` | `She saved 300 people [1][4]`, or `unverified: single source` | [F1] |
| 4 | Is a later retelling presented as a primary source? | Blog post quoting a diary, listed as "diary" | `secondary: quotes diary; original not found` | [F1] |
| 5 | Is a fact mixed with invention without labels? | `He whispered goodbye to the ship` in the Fact list | Moved to `Dramatization needed` | [F2] |
| 6 | Does a quote, date, or number appear with no source number? | `In 1887, 4,000 died.` | `In 1887, about 4,000 died [2]; [3] gives 2,500.` | [F3] |
| 7 | Does the candidate claim originality as a fact? | `No one has ever told this story.` | `Search found two videos on the event; neither uses the daughter's view.` | [proposal] |
| 8 | Is the same subject and angle already in `ideas-log.md`? | Shown again as new | Dropped; counted in the report | [proposal] |
| 9 | Is a rating given without a reason, or all ratings "high"? | `Originality: high` | `Originality: medium — event is well covered; angle is not` | [proposal] |
| 10 | Is the angle the most common summary of the subject? | `The Titanic hit an iceberg and sank` | `The baker who survived two hours in the water` | [proposal] |
| 11 | Does feasibility ignore the project's method and time budget? | Battle with thousands, rated high for a solo AI-image project | Rated low, with the crowd count as the reason | [proposal] |
| 12 | Does the output include scenes or dialogue? | A drafted opening scene | `Why it is a story` in three lines only | [proposal] |
| 13 | Was the idea shown to the user before being appended to `ideas-log.md`? | Log unchanged after the run | Log has one new line per idea, dated | [proposal] |

Verdict format:

```
REJECT #3 — I-4: "The crew ate the ship's cat" — one source [2], not labeled unverified.
```
