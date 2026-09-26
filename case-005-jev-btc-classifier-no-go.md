# Case #005: A Pre-Registered NO-GO for an LLM Classifier on BTC 4H Price Direction

> **TL;DR:** We ran a pre-registered historical replay to test whether a cheap classification model ($0.0001 per decision) can predict BTC's next-4h price direction well enough to trade. Result: **NO-GO**, confirmed by our own gates and independently reproduced by an external reviewer who recomputed every number from raw run files. A second external reviewer, searching for a better design instead, proposed alternatives that on inspection didn't survive their own arithmetic or a citation check. The measurement harness itself had a real bug — not one that changes the verdict, but one worth fixing and publishing here: a report generator that accepted corrupted input without complaint.

## Context

The question: does an LLM, asked a simple multiple-choice question ("up" or "down") about the next 4-hour BTC candle, do better than chance once you account for trading costs? This is not a "vibe check" — we pre-registered the whole design (thresholds, data split, gates) before looking at test results, and used a shuffled-input control to catch anything that looked like signal but wasn't.

**Fixed constraints (decided before any data was touched):** BTC perpetual on Hyperliquid, 1x leverage, long-only, isolated margin, ~€250 working capital. No shorts, no altcoins, nothing below 1-hour bars.

**Data:** 4,381 BTC 4h candles (730 days) plus hourly funding rates from the Hyperliquid public API. First 336 bars as warm-up; the rest split 50/50 in time into DEV (feature/window selection only) and TEST (the one-shot verdict).

**Model:** a classification-only LLM ("Jev" by TypeSafe) answering one `choice` question — up or down — per bar, with a stated confidence.

## Method

Ten indicator groups × eight lookback windows; one window per group chosen on DEV only, by average rank of Spearman correlation against next-bar return across four DEV blocks. Trading rule: flat → long when `p_up ≥ 0.65`; long → flat when `p_up ≤ 0.50`. Fill at next open, 1bp slippage, three cost scenarios, hourly funding subtracted. Null control: same TEST ids and labels, inputs shuffled across bars (seed 42).

**Five pre-registered gates, all required to pass:**

| Gate | Requirement |
|---|---|
| G1 | Accuracy ≥ 0.60 on bars with confidence ≥ 0.65 (n ≥ 100) |
| G2 | Share of bars with confidence ≥ 0.65 is ≥ 15% |
| G3 | ≥ 20 round trips over the TEST period |
| G4 | Beats buy-and-hold in ≥ 3 of 4 TEST blocks |
| G5 | Real accuracy exceeds shuffled-control accuracy by ≥ 2 standard errors |

## Results

| Gate | Value | Threshold | Result |
|---|---|---|---|
| G1 | n=1539, accuracy=0.4886 | n≥100, acc≥0.60 | **FAIL** |
| G2 | 0.7611 | ≥0.15 | PASS |
| G3 | 98 round trips | ≥20 | PASS |
| G4 | 3/4 blocks | ≥3/4 | PASS |
| G5 | real − shuffled = −0.0289 | ≥+0.0255 | **FAIL** |

**VERDICT: NO-GO** (failed G1 and G5). Real high-confidence accuracy (48.9%) is *below* chance, and *below* the shuffled control (51.7%) — the model is not just uninformative here, it's mildly anti-correlated on the bars it claims to be confident about. Overall directional accuracy across all TEST bars was 49.1% against a mean stated confidence of 78.7% — badly overconfident.

**G4 note:** passed only because three of four TEST blocks were falling markets, where a partly-flat long-only rule loses less by construction. We consider this gate uninformative for this run, not evidence of skill.

Two smaller, model-free tests were run alongside this (candle patterns on DEV, and a one-shot reversal rule on TEST) — both also failed their pre-registered gates. Full detail in `reports/` (private repo, referenced below).

## Independent Verification

Rather than trust our own numbers, we sent the full evidence package — pre-registration, code, raw run files, our own reports — to an external reviewer (ChatGPT) with one instruction: **write your verdict before opening our reports, then recompute everything yourself from the raw files.**

Their independent script (does not import our reporting or accuracy functions):

```python
import json
import math
from pathlib import Path

ROOT = Path('/mnt/data/jev_independent_review/jev-external-review-2026-09-26/repo')
CUT = 0.65  # PLAN.md, G1 threshold


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def load_run(name):
    records = read_jsonl(ROOT / 'jev-eval-harness' / 'runs' / name)
    metadata = next(r['_meta'] for r in records if '_meta' in r)
    rows = [r for r in records if '_meta' not in r]
    assert len(rows) == metadata['n']
    assert len({r['id'] for r in rows}) == len(rows)
    assert all(not r.get('error') for r in rows)
    for row in rows:
        p = row['probabilities']
        assert set(p) == {'up', 'down'}
        assert all(math.isfinite(v) and 0 <= v <= 1 for v in p.values())
        assert math.isclose(sum(p.values()), 1)
    return rows


def accuracy(rows):
    selected = [r for r in rows if max(r['probabilities'].values()) >= CUT]
    hits = sum(('up' if r['probabilities']['up'] >= r['probabilities']['down']
                else 'down') == r['label'] for r in selected)
    return len(selected), hits, hits / len(selected)


real = load_run('btc-direction_real_rerun.jsonl')
nr, hr, ar = accuracy(real)
print(f'a: TEST rows={len(real)}, n={nr}, hits={hr}, accuracy={ar:.12f}')
shuffled = load_run('btc-direction_shuffled_rerun.jsonl')
ns, hs, acs = accuracy(shuffled)
print(f'b: TEST rows={len(shuffled)}, n={ns}, hits={hs}, accuracy={acs:.12f}')
print(f'b: real-minus-shuffled={ar-acs:.12f}')
```

Their actual output:

```text
a: TEST rows=2022, n=1539, hits=752, accuracy=0.488628979857
b: TEST rows=2022, n=1544, hits=799, accuracy=0.517487046632
b: real-minus-shuffled=-0.028858066775
```

Byte-identical to our own gate report. They also independently checked all 2,022 TEST labels against the raw candle closes (0 mismatches), reproduced the seeded shuffle (0 mismatches), and verified no look-ahead at 50 spot-checked locations (0 causality failures).

**Their verdict, written before opening our reports:**

> "NO-GO stands for the frozen classifier, its stored rerun outputs, and its registered gate rule. Remaining implementation defects do not establish a rescue. Failure of this design is not proof that the inputs contain no tradable information."

That distinction matters: they found five implementation defects in our code (a Spearman tie-breaking bug, a volatility window off by one return, a stale comment, an overly narrow significance formula for G5, and — the one that mattered — a report generator that would accept a truncated, duplicated, or NaN-filled run file and print a verdict anyway without complaint). None of the five change the outcome. But the last one is a real fail-closed defect in reusable measurement code, and we've fixed it (see below).

They also caught a documentation error in our own write-up: we'd claimed no candle pattern reached its statistical threshold; in fact one (`hammer`) did clear the z-cutoff but failed on sample size (n=31 against a required n≥100). The corrected finding is "no pattern clears every gate," not "no pattern is statistically significant" — a narrower and more accurate claim, now fixed in our records.

## A Second Opinion, Looking for a Way It Could Work

We also asked a second reviewer (Gemini) a different question: not "is this correct," but "is there a better design that could actually work?" — diverge across horizons, targets, and model roles; grade every proposal's evidence; kill anything that can't clear trading costs; converge on one falsifiable recommendation.

Their arithmetic on cost was worth having independent of anything else: on Hyperliquid, taker fees plus slippage run ~0.11% per round trip. At three trades a day that's ~10% of capital lost to fees alone in a month — the same wall our own numbers hit (gross return before costs +0.055, after fees and slippage −0.078).

Their primary recommendation — daily news-sentiment classification instead of price-data classification — rested on three cited papers. We checked all three:

- One (Lopez-Lira & Tang) is real, but reports that the strategy needs ~190% daily portfolio turnover and becomes unprofitable above 20bp round-trip costs — the opposite of supporting evidence.
- One (Brugière & Turinici) is real, and found a purpose-built transformer *couldn't* predict returns either — only volatility. Also not supporting evidence for their proposal.
- One ("Roa et al.") we could not locate. The closest real paper on the same task (Peskoff et al.) reports an F1 of 0.57 — mediocre, not the "flawless" parsing claimed.

So: neither external round reopens the trading question. But both, independently, land on the same underlying point — this class of model belongs on text classification, not on numerical price series. That's a useful negative result in its own right, and it's the reasoning behind steering this classifier toward a text-classification application elsewhere in our stack instead.

## Current Status

**Closed**, pending a genuinely new, pre-registered hypothesis tested on data that didn't exist at the time of this replay (both DEV and TEST are now "used" — testing on them again would just be re-fitting to a known answer, not a new test).

## Lessons Learned

### 1. Write your verdict before you read anyone else's
The reviewer wrote a full verdict from raw files before opening our own reports. That's the only way a "second opinion" is actually independent instead of an echo of the first one.

### 2. A report generator that never refuses input isn't a safety net
Three deliberately corrupted copies (truncated, duplicated row, NaN probabilities) were all silently accepted and produced a clean-looking verdict. The real run files were fine — but the gate was not. Fail-closed validation (row-count match, unique IDs, exact ID-set agreement between real/shuffled/golden, finite bounded probabilities) is now part of the harness.

### 3. Citations need checking, not just collecting
A well-formatted `[PROVEN]` label next to a real author name reads as settled. Two of three didn't survive five minutes of checking what the cited paper actually concluded.

### 4. A negative result with a repaired, reusable measurement pipeline is not a failure
The trading hypothesis died. The harness — pre-registration discipline, shuffled-control methodology, the (now-fixed) fail-closed reporter — didn't, and is going straight into the next application of this classifier.

## Open Question — Feedback Welcome

We're publishing this with the full pre-registration and reproduction code because we're genuinely unsure where, if anywhere, this could go. If you can see a design in this space that survives (a) the ~0.11% round-trip cost floor on this venue, (b) a pre-registered gate, and (c) testing on data that postdates this writeup — we'd like to hear it, wrong or right.

## Files

- `PLAN.md` — the pre-registered plan with fixed gate definitions *(referenced; not yet included in this repo — available on request, part of the private measurement harness)*
- `tools/replay/` — fetch, features, golden-set builder, checks, report generator *(referenced; not yet included in this repo)*
- The independent-verification script above is reproduced here in full; it is self-contained and doesn't depend on the rest of the harness.

## References

- Lopez-Lira, A. & Tang, Y., "Can ChatGPT Forecast Stock Price Movements?", *Journal of Financial Economics* (2023/2026)
- Brugière, P. & Turinici, G., "Transformer for Time Series: an Application to the S&P500", arXiv:2403.02523 (2024)
- Peskoff, D. et al. on zero-shot LLM hawkish/dovish classification (2023) — closest real match to a cited-but-unlocated Fed-communication paper

---

**Status:** ✅ Closed (NO-GO), externally confirmed
**Time invested:** multi-day design + replay, plus two independent external reviews
**Outcome:** Trading hypothesis rejected; measurement harness repaired and reused; classifier redirected to a text-classification application
