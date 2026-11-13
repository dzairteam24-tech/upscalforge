# YouTube Packaging: rejection checklist

Answer each question yes or no. Any "yes" rejects the item. Quote the offending title, field, or line in the verdict. This list can only reject; passing it does not prove quality.

Source labels: `[F#]` refers to a finding in the master library's `research/youtube-packaging.md`; `[proposal]` means no opened source supports it yet.

| # | Reject if yes | Fail example | Pass example | Source |
|---|---|---|---|---|
| 1 | Does the title or thumbnail promise something the video does not deliver? | `The Keeper Who Vanished` (he does not vanish) | `The Keeper Who Refused to Leave` — delivered in S06 | [F1][F3] |
| 2 | Does the thumbnail show something not in the video? | A shipwreck that is never shown | The lit lamp from S07-03 | [F2] |
| 3 | Does the thumbnail hold more than one idea? | Keeper + ship + storm + map + text | Keeper's face lit by the lamp | [proposal] |
| 4 | Does the thumbnail text repeat the title? | Title: `40 Nights Alone`; text: `40 NIGHTS ALONE` | Text: `NO ONE CAME` | [proposal] |
| 5 | Is the thumbnail text longer than four words? | `The true story of a forgotten hero` | `40 NIGHTS` | [proposal] |
| 6 | Is a number given for search volume, CTR, or expected views? | `This title should get 8% CTR` | No prediction; reasoning in words | [proposal] |
| 7 | Is advice presented as how "the algorithm" works without an official source? | `The algorithm boosts titles under 50 characters` | `opinion: shorter titles are less likely to be cut off` | [proposal] |
| 8 | Is the title all caps, or does it use stacked punctuation? | `YOU WON'T BELIEVE THIS!!!` | `He Kept the Lamp Lit for 40 Nights` | [proposal] |
| 9 | Does the description stuff keywords or tags? | A block of 30 comma-separated terms | Two plain sentences, then details | [F4] |
| 10 | Are tags treated as a main discovery tool? | 40 tags, described as "key to ranking" | Five tags, noted as minor | [F5] |
| 11 | Do the five titles all use the same approach? | Five questions | Question, fact, character, stakes, contrast | [proposal] |
| 12 | Does the image prompt re-describe a character instead of using the bible's canonical block? | `an old sailor with a beard` | Block for C01 pasted verbatim | [proposal] |
| 13 | For a Short, is a designed thumbnail delivered with no opening-shot recommendation? | Three thumbnail designs only | Opening shot S01-01 named, with reason | [proposal] |
| 14 | Is the "made for kids" question left unanswered? | Field missing | `Not made for kids: theme of death at sea; user to confirm` | [proposal] |
| 15 | Is official guidance mixed with opinion without labels? | Unlabeled tips list | Each line tagged `official` or `opinion` | [proposal] |

Verdict format:

```
REJECT #1 — Title 3: "The Lighthouse Murder" — no murder occurs in the screenplay.
```
