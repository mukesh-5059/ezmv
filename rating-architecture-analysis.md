# Rating Architecture Analysis & Proposal

## The Problem

Your current system extracts **only IMDb ratings + IMDb votes** from mdblist, falling back to `score / 10` when IMDb is absent. This creates three compounding issues for a Tamil/regional-focused app:

### 1. MDBList's `score` is Actively Hostile to Regional Cinema

MDBList's weighted `score` applies a **minimum-votes baseline penalty per source**. A Tamil film with 25,000 IMDb votes (rated 8.5) but only 20 TMDB votes, 5 Trakt votes, and 0 RT/Metacritic gets its `score` **crushed to 30–50 out of 100** — because most Western-centric sources have near-zero coverage for South Indian cinema.

This means your current fallback (`score / 10`) actively punishes exactly the movies your app prioritizes.

### 2. Vote Count Black Hole

[`parseVotes`](file:///home/mukes/dev/movies/backend_revised/src/services/mdblist.ts#L87-L93) returns `0` when IMDb votes are missing — no fallback to TMDB, Letterboxd, or any other source. Combined with your `ORDER BY rating DESC, votes DESC` sort in [lanes.ts](file:///home/mukes/dev/movies/backend_revised/src/services/lanes.ts#L68), regional titles with real engagement on other platforms get buried at the bottom of "Top Rated" lanes.

### 3. Inconsistency Between Sync and Worker

Your [sync script](file:///home/mukes/dev/movies/backend_revised/scripts/sync_catalog_to_d1.py#L178-L181) already uses Letterboxd-first logic for filtering (`val = lr if lr is not None else ir`), but the [worker's parseRating](file:///home/mukes/dev/movies/backend_revised/src/services/mdblist.ts#L76-L84) doesn't replicate this. Same movie can get different ratings depending on whether it came through the daily sync or an on-demand lookup.

---

## What MDBList Gives You (That You're Throwing Away)

| Source | Scale | Regional Coverage | Currently Used? |
|---|---|---|---|
| `imdb` | 0–10 | ✅ Good (but brigade-prone) | ✅ Primary |
| `letterboxd` | 0–5 (normalized 0–100) | ✅ Growing among Indian cinephiles | ❌ Discarded |
| `tmdb` | 0–100 | ⚠️ Low vote counts | ❌ Discarded |
| `trakt` | 0–100 | ❌ Western-skewed | ❌ Discarded |
| `tomatoes` | 0–100 | ❌ Near-zero for regional | ❌ Discarded |
| `popcorn` | 0–100 | ❌ Near-zero for regional | ❌ Discarded |
| `metacritic` | 0–100 | ❌ Near-zero for regional | ❌ Discarded |
| `score` | 0–100 (weighted) | ⚠️ Deflated for regional | ⚠️ Fallback only |
| `score_average` | 0–100 (unweighted) | ✅ Fairer | ❌ Discarded |

> [!IMPORTANT]
> Every provider in `ratings[]` has a **pre-normalized `score` field (0–100)** alongside the raw `value`. This eliminates the scale-conversion headache — you can compare apples to apples across all sources.

---

## Proposed Architecture: Weighted Multi-Source Rating

### Core Idea

Instead of one `rating` + one `votes` column, compute a **composite rating** from all available sources, weighted by relevance to your audience.

### Rating Strategy: Priority Cascade with Adaptive Weights

```
┌─────────────────────────────────────────────────────┐
│              For each title from MDBList             │
│                                                     │
│  Collect all sources where value != null             │
│  Normalize each to 0–10 scale (use r.score / 10)    │
│                                                     │
│  Apply weight per source:                           │
│    imdb:        0.45  (largest sample, most recognized)
│    letterboxd:  0.30  (cinephile signal, less brigading)
│    tmdb:        0.15  (decent metadata, decent coverage)
│    trakt:       0.05  (niche, Western-skewed)          
│    tomatoes:    0.03  (critic signal when available)   
│    popcorn:     0.02  (audience RT when available)     
│                                                     │
│  Redistribute missing weights proportionally         │
│  across available sources                            │
│                                                     │
│  composite_rating = Σ(normalized_score × weight)     │
│  total_votes = Σ(votes across all available sources) │
│                                                     │
│  Apply minimum-votes confidence gate:               │
│    if total_votes < 50 → flag as "low confidence"   │
└─────────────────────────────────────────────────────┘
```

### Why These Weights?

- **IMDb (0.45)**: Largest user base in India. Despite brigading on star vehicles, IMDb's own Bayesian filter handles most of it. Still the most recognized rating for Indian users.
- **Letterboxd (0.30)**: The **key differentiator** for regional cinema quality. Less susceptible to fan-war brigading. Films like *Super Deluxe*, *Jai Bhim*, *Maharaja* get thoughtful review distributions here. This is your best signal for "is this actually a good Tamil film."
- **TMDB (0.15)**: Rich multilingual metadata (Tamil posters, translated overviews). Low vote counts mean it shouldn't dominate, but it adds signal.
- **Trakt/RT/Popcorn (0.10 combined)**: Useful for Hollywood/crossover titles, nearly absent for regional. The proportional redistribution handles this gracefully — when they're missing, their weight flows to IMDb + Letterboxd.

### Schema Change

```sql
-- Replace the single rating/votes with multi-source storage
CREATE TABLE IF NOT EXISTS ratings (
    imdb_id TEXT PRIMARY KEY,
    -- Individual source ratings (0-10 normalized) + votes
    imdb_rating REAL,
    imdb_votes INTEGER DEFAULT 0,
    letterboxd_rating REAL,
    letterboxd_votes INTEGER DEFAULT 0,
    tmdb_rating REAL,
    tmdb_votes INTEGER DEFAULT 0,
    trakt_rating REAL,
    trakt_votes INTEGER DEFAULT 0,
    -- Computed composite (what the API returns)
    rating REAL NOT NULL DEFAULT 0,       -- weighted composite (0-10)
    votes INTEGER NOT NULL DEFAULT 0,     -- sum of all source votes
    source_count INTEGER NOT NULL DEFAULT 0, -- how many sources contributed
    updated_at INTEGER NOT NULL
);
```

> [!TIP]
> Storing individual source ratings lets you recompute composites if you change weights later — without re-fetching from mdblist. It also enables a future "ratings breakdown" UI showing per-source scores.

### The parseRating / parseVotes Replacement

```typescript
interface CompositeRating {
  rating: number;       // 0-10 composite
  votes: number;        // total across all sources
  sourceCount: number;  // how many sources contributed
  sources: {            // individual, for DB storage
    imdb?: { rating: number; votes: number };
    letterboxd?: { rating: number; votes: number };
    tmdb?: { rating: number; votes: number };
    trakt?: { rating: number; votes: number };
  };
}

const SOURCE_WEIGHTS: Record<string, number> = {
  imdb: 0.45,
  letterboxd: 0.30,
  tmdb: 0.15,
  trakt: 0.05,
  tomatoes: 0.03,
  popcorn: 0.02,
};

static computeRating(item: MdblistItem): CompositeRating {
  const sources: CompositeRating['sources'] = {};
  let weightedSum = 0;
  let totalWeight = 0;
  let totalVotes = 0;

  if (!Array.isArray(item.ratings)) {
    // Last-resort fallback to score_average (fairer than score)
    const avg = item.score_average ?? item.score;
    const rating = (typeof avg === 'number' && avg > 0) ? Number((avg / 10).toFixed(1)) : 0;
    return { rating, votes: 0, sourceCount: 0, sources: {} };
  }

  for (const r of item.ratings) {
    const weight = SOURCE_WEIGHTS[r.source];
    if (!weight || typeof r.score !== 'number') continue;

    const normalized = r.score / 10; // r.score is 0-100 → 0-10
    const votes = r.votes ?? 0;

    weightedSum += normalized * weight;
    totalWeight += weight;
    totalVotes += votes;

    if (['imdb', 'letterboxd', 'tmdb', 'trakt'].includes(r.source)) {
      sources[r.source as keyof typeof sources] = { rating: Number(normalized.toFixed(1)), votes };
    }
  }

  if (totalWeight === 0) {
    const avg = item.score_average ?? item.score;
    const rating = (typeof avg === 'number' && avg > 0) ? Number((avg / 10).toFixed(1)) : 0;
    return { rating, votes: 0, sourceCount: 0, sources: {} };
  }

  // Redistribute to make weights sum to 1.0
  const rating = Number((weightedSum / totalWeight).toFixed(1));
  const sourceCount = Object.keys(sources).length;

  return { rating, votes: totalVotes, sourceCount, sources };
}
```

### How This Plays Out — Concrete Examples

#### Tamil Film: *Maharaja* (2024)
| Source | Raw Value | Normalized (0-10) | Votes | Weight |
|---|---|---|---|---|
| IMDb | 8.1 | 8.1 | 32,000 | 0.45 |
| Letterboxd | 3.9/5 | 7.8 | 15,200 | 0.30 |
| TMDB | 76 | 7.6 | 280 | 0.15 |
| Trakt | – | – | – | – |
| RT | – | – | – | – |

**Current system**: `rating = 8.1, votes = 32,000` (IMDb only)
**Proposed**: `rating = 7.9, votes = 47,480, sourceCount = 3`
→ Minor rating change, but **47k total votes** vs 32k gives much better ranking signal.

#### Tamil Film with no IMDb rating: *Maayam*
| Source | Raw Value | Normalized (0-10) | Votes |
|---|---|---|---|
| IMDb | – | – | – |
| TMDB | 70 | 7.0 | 45 |
| Letterboxd | 3.2/5 | 6.4 | 120 |

**Current system**: `rating = 0 (or score/10 fallback), votes = 0` → **invisible**
**Proposed**: `rating = 6.6, votes = 165, sourceCount = 2` → visible and ranked fairly

#### Hollywood Blockbuster: *Jaws*
| Source | Normalized | Votes | Weight |
|---|---|---|---|
| IMDb | 8.1 | 673,852 | 0.45 |
| Letterboxd | 8.0 | 876,082 | 0.30 |
| TMDB | 7.6 | 10,114 | 0.15 |
| Trakt | 7.8 | 14,033 | 0.05 |
| RT Critics | 9.7 | 102 | 0.03 |
| RT Audience | 9.1 | 41,105 | 0.02 |

**Proposed**: `rating = 8.1, votes = 1,615,288, sourceCount = 6`
→ All sources present; weights work as-is. No redistribution needed.

---

## API Changes

### Option A: Minimal — Drop-In Replacement (Recommended to start)
Keep the API contract unchanged (`rating` + `vote_count`). The composite computation is internal. Frontend doesn't change at all.

### Option B: Enhanced — Expose Source Breakdown
Add optional `rating_sources` in the detail endpoint:
```json
{
  "rating": 7.9,
  "vote_count": 47480,
  "rating_source_count": 3,
  "rating_sources": {
    "imdb": { "rating": 8.1, "votes": 32000 },
    "letterboxd": { "rating": 7.8, "votes": 15200 },
    "tmdb": { "rating": 7.6, "votes": 280 }
  }
}
```
This enables a future "ratings breakdown" chip UI (like Letterboxd's own detail page).

---

## What Changes, File by File

| File | Change |
|---|---|
| [`schema.sql`](file:///home/mukes/dev/movies/backend_revised/schema.sql) | Expand `ratings` table with per-source columns |
| [`types/upstream.ts`](file:///home/mukes/dev/movies/backend_revised/src/types/upstream.ts) | Add `score_average` to `MdblistItem` |
| [`services/mdblist.ts`](file:///home/mukes/dev/movies/backend_revised/src/services/mdblist.ts) | Replace `parseRating`/`parseVotes` with `computeRating` |
| [`services/catalog.ts`](file:///home/mukes/dev/movies/backend_revised/src/services/catalog.ts) | Update upsert to store per-source + composite fields |
| [`scripts/sync_catalog_to_d1.py`](file:///home/mukes/dev/movies/backend_revised/scripts/sync_catalog_to_d1.py) | Mirror the same composite logic in Python for daily sync |
| [`services/lanes.ts`](file:///home/mukes/dev/movies/backend_revised/src/services/lanes.ts) | No change needed — `ORDER BY rating DESC, votes DESC` works better with composite votes |
| [`routes/movies.ts`](file:///home/mukes/dev/movies/backend_revised/src/routes/movies.ts) | Optional: expose `rating_sources` in detail endpoint |

---

## Open Questions for You

1. **Weights**: The proposed IMDb 0.45 / Letterboxd 0.30 / TMDB 0.15 split — does this match your intuition for your audience? If you want Letterboxd to dominate for Tamil content, we could bump it to 0.40 and drop IMDb to 0.35.

2. **`score_average` as last-resort fallback**: When no individual sources have ratings, should we fall back to mdblist's `score_average` (unweighted mean — fairer than `score` for regional content) or just show `0`?

3. **API surface**: Start with Option A (internal-only, no frontend change) or go directly to Option B (expose per-source breakdown)?

4. **Migration**: The schema change adds columns to `ratings`. This needs a D1 migration. Want me to generate that alongside the code changes?
