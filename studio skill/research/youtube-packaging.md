# Research: YouTube Packaging

Version 0.1.0 — 2026-11-13

## Limits of this research (read first)

`support.google.com` was blocked in the build session, so **no official YouTube page was opened**. Findings F1 to F3 are search-engine excerpts of official Help pages; F4 and F5 are third-party pages describing official guidance. None counts as verified. For this reason the Skill instructs Claude to open the official pages in each production session and to state no technical limits from memory.

## Questions

1. What does YouTube officially prohibit in titles and thumbnails?
2. What does YouTube officially recommend for titles and thumbnails?
3. What is the official role of tags and descriptions?
4. How do Shorts differ in packaging?
5. What are the "made for kids" rules?

## Findings

| # | Claim (as excerpted by search) | Source | Date seen | Type | Resulting rule |
|---|---|---|---|---|---|
| F1 | The spam policy lists "malicious clickbait": misleading titles, thumbnails, or descriptions that trick users into a video that does not deliver what was promised. | https://support.google.com/youtube/answer/2801973 | 2026-11-13 | official page, search excerpt only | Every title and thumbnail names the scene that delivers it; checklist #1 |
| F2 | The thumbnails policy disallows a thumbnail that misleads viewers into thinking they will see something that is not in the video. | https://support.google.com/youtube/answer/9229980 | 2026-11-13 | official page, search excerpt only | Thumbnail tied to a shot ID; checklist #2 |
| F3 | Official tips say titles should be accurate, since viewers who feel misled stop watching, which can affect discovery; the performance FAQ advises against deceptive or clickbait titles and thumbnails. | https://support.google.com/youtube/answer/12340300 ; https://support.google.com/youtube/answer/141805 | 2026-11-13 | official page, search excerpt only | Honesty rule; no performance predictions; checklist #1 |
| F4 | Adding excessive tags to the description is against YouTube's spam policies; tags belong in the tags field. | Third-party pages citing YouTube Help (for example https://socialk.it/en/blog/youtube-hashtags-and-tags) | 2026-11-13 | search summary, page not opened (third party) | No keyword lists in the description; checklist #9 |
| F5 | YouTube's own guidance is said to state that tags play a minimal role in discovery and matter mostly for commonly misspelled terms. | Third-party pages citing https://support.google.com/youtube/answer/146402 | 2026-11-13 | search summary, page not opened (third party) | Tags optional and short; checklist #10 |

## Unresolved

- Q4 (Shorts) and Q5 (made for kids): official pages not reached. The Shorts handling and the audience field are proposals; the Skill tells Claude to check the official pages each time.
- All technical limits (title length, thumbnail size, hashtag count): not confirmed, and deliberately left out of the Skill.

## Rules labeled as proposals

Five title approaches, four-word thumbnail text limit, one idea per thumbnail (from the build brief), title-and-thumbnail-as-pair rule, checklist #3 to #8 and #11 to #15.
