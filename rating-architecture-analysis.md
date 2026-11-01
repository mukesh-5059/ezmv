# Movie Catalog & Rating Architecture

This document specifies the end-to-end rating calculation algorithm, source ingestion pipelines, and dynamic lane selection mechanics used in the platform.

---

## 1. Catalog Provenance & Data Ingestion

### Upstream Sources
All raw movie metadata and multi-platform ratings are ingested via the official REST API of **MDBList** (`https://api.mdblist.com/`):
- **Tamil Regional Catalog**: List `218335` (contains 6,690+ Tamil titles).
- **Pan-India Cross-Industry Catalog**: List `76398` (contains curated South Indian blockbusters across Tamil, Telugu, Malayalam, and Kannada).

### Two-Stage Ingestion Pipeline
1. **Lane List Ingestion**:
   - Fetches candidate items via `GET /lists/{list_id}/items?limit=1000&append_to_response=genres,poster,description,ratings`.
   - Queries include server-side filters such as `sort=releasedigital&sort_order=desc` for digital releases or `filter_genre=comedy`.
2. **Multi-Source Batch Enrichment**:
   - MDBList list responses provide basic info, but full multi-platform ratings (Letterboxd, Rotten Tomatoes Critics, Popcorn Audience, Trakt, Metacritic) require the detailed movie endpoint.
   - The sync script chunks unique IMDb IDs into batches of 100 and queries `POST https://api.mdblist.com/imdb/movie/` with `{'ids': chunk}`.
   - Results are persisted locally in `/tmp/mdblist_batch_cache.json` to prevent quota exhaustion.
3. **Database Layer (Local SQLite / Cloudflare D1)**:
   - Ingested entities are normalized into:
     - `movies`: Core metadata (IMDb ID, TMDB ID, title, year, release date, runtime, poster, backdrop, overview, normalized genre slugs).
     - `ratings`: Cleaned ratings array JSON, Bayesian composite `rating_score`, total verified `votes`.
     - `lane_entries`: Mapping of `(lane_id, imdb_id, rank)`.
     - `v_movies`: Unified view joining `movies` and `ratings` for indexed querying and filtering.

---

## 2. Multi-Source Composite Rating Algorithm

### Philosophy
Standard single-source metrics (e.g. raw IMDb score) fail for regional cinema due to fan brigading, low sample sizes on Western aggregators, and uncorroborated astroturfing. The rating algorithm combines **calibrated qualification gates**, **platform relevance weighting**, and **source-count Bayesian shrinkage with an era curve**.

Implementation references:
- Python Sync Script: [sync_catalog_to_d1.py](file:///home/mukes/dev/movies/backend_revised/scripts/sync_catalog_to_d1.py#L65-L183)
- Cloudflare Worker Service: [mdblist.ts](file:///home/mukes/dev/movies/backend_revised/src/services/mdblist.ts#L60-L167)

---

### Step 1: Qualification Gates (`MIN_VOTES`)
To prevent single-user review attacks from polluting aggregate scores, each rating source must satisfy a minimum vote threshold before its score is admitted:

| Provider | Min Votes | Rationale |
|---|---|---|
| `imdb` | **500** | Raised from 100 to eliminate micro-budget films with 15 brigaded 10/10 ratings |
| `letterboxd` | **50** | Cinephile community engagement floor |
| `tmdb` | **20** | General community engagement floor |
| `trakt` | **20** | Media tracking user floor |
| `popcorn` (RT Audience) | **50** | General audience floor |
| `tomatoes` (RT Critics) | **10** | Verified critic review threshold |
| `metacritic` | **5** | Professional review threshold |

If a platform has fewer votes than its threshold, its rating and votes are discarded from the weighted average.

---

### Step 2: Platform Relevance Weighting
Qualified ratings are normalized to a 10-point scale ($r_i = \text{score} / 10$) and assigned weights based on relevance to Indian regional cinema:

| Provider | Weight ($w_i$) | Relevance Justification |
|---|---|---|
| `letterboxd` | **0.35** | Highest cinephile signal-to-noise ratio, highly resistant to automated brigading |
| `imdb` | **0.30** | Primary volume driver and broad-audience benchmark |
| `tmdb` | **0.15** | Neutral metadata community baseline |
| `trakt` | **0.10** | Active media trackers |
| `popcorn` | **0.05** | Auxiliary general audience signal |
| `tomatoes` | **0.025** | Rare for regional titles, but high signal when available |
| `metacritic` | **0.025** | Highly conservative academic/critic signal |

The raw weighted average is:
$$\text{raw\_rating} = \frac{\sum_{i=1}^{k} (r_i \times w_i)}{\sum_{i=1}^{k} w_i}$$
$$\text{total\_votes} = \sum_{i=1}^{k} v_i$$

---

### Step 3: Source-Count Bayesian Shrinkage
Raw ratings are pulled toward a global regional prior mean ($C = 6.8$) using a Bayesian dampening factor ($m$). The value of $m$ scales dynamically based on the number of **independent, qualified sources** ($N$):

```
                       ┌── N = 1 source  ──> m = 10,000 (Severe skepticism)
                       │
m baseline by sources ─┼── N = 2 sources ──> m = 3,000  (Moderate corroboration)
                       │
                       └── N >= 3 sources ─> m = 1,000  (Cross-platform consensus)
```

- **Single-Source Protection**: An obscure indie with 600 votes only on IMDb and 0 on Letterboxd/TMDB gets $m = 10,000$. Even with a raw 9.5 rating, its score shrinks to ~7.0.
- **Corroborated Blockbusters**: A movie reviewed across IMDb, Letterboxd, and TMDB gets $m = 1,000$, allowing its true score to emerge with minimal resistance.

---

### Step 4: Era Curve Calibration (Recency Penalty & Classic Boost)
Movie age is calculated in fractional years:
$$\text{age} = \max\left(0, \frac{\text{now} - \text{release\_date}}{365.25}\right)$$

1. **Recency Penalty (Exponential Decay)**:
   Protects against opening-window fan hype and review bombing during the first 30–90 days:
   $$\text{penalty} = 0.5 \times e^{-\text{age} \times 1.5}$$
2. **Classic Boost (Survivorship Curve)**:
   Accounts for archival classics (pre-2005) whose online vote volume is artificially constrained by internet penetration in India:
   $$\text{boost} = 0.5 \times \text{clamp}\left(\frac{\text{age} - 3}{25}, 0, 1\right)$$
3. **Anti-Double-Penalty Factor**:
   If a recent movie has already been cross-corroborated across 3+ platforms, the recency penalty is softened:
   $$\text{rawEra} = \text{clamp}(1.0 + \text{penalty} - \text{boost}, 0.5, 1.5)$$
   $$\text{eraModifier} = 1.0 + \frac{\text{rawEra} - 1.0}{N}$$
   $$m \leftarrow m \times \text{eraModifier}$$

---

### Step 5: Final Score Formula
$$\text{rating\_score} = \text{round}\left( \frac{\text{total\_votes}}{\text{total\_votes} + m} \times \text{raw\_rating} + \frac{m}{\text{total\_votes} + m} \times C, 1 \right)$$

- **Unverified Fallback Stripping**: If no sources meet their minimum vote gates ($N = 0$), the movie receives `rating_score = 0.0` and `votes = 0`. Arbitrary fallback scores (`score_average / 10`) are strictly banned to prevent unverified titles from ranking at #1.

---

## 3. Dynamic Lane Selection & Ranking

All lanes apply common quality baselines before lane-specific logic:
- `poster_path != ''` (must have valid artwork)
- `runtime >= 85` minutes (filters out short films and clips)
- Excludes genres: `documentary`, `short`, `animation`

Implementation reference: [sync_catalog_to_d1.py#L502-L574](file:///home/mukes/dev/movies/backend_revised/scripts/sync_catalog_to_d1.py#L502-L574)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Dynamic Lane Matrix                             │
├───────────────┬──────────────┬──────────────┬──────────────────────────┤
│ Lane ID       │ Window       │ Vote Floor   │ Ranking Criterion        │
├───────────────┼──────────────┼──────────────┼──────────────────────────┤
│ trending      │ Last 180 d   │ >= 400 total │ Vote Velocity (dv/dt)    │
│ new_releases  │ Last 90 d    │ >= 400 IMDb  │ release_date DESC        │
│ new_ott       │ Last 180 d   │ >= 400 total │ MDBList releasedigital   │
│ top_rated     │ All-time     │ >= 5000      │ rating_score DESC        │
│ comedy        │ All-time     │ >= 500       │ votes DESC               │
│ pan_india     │ All-time     │ >= 5000      │ votes DESC               │
└───────────────┴──────────────┴──────────────┴──────────────────────────┤
```

---

### Detailed Lane Mechanics

### 1. Trending Now (`trending`)
- **Objective**: Surface movies currently capturing audience attention without letting multi-year-old blockbusters (*Leo*, *Vikram*) camp in Trending permanently.
- **Window**: Released in the last 180 days ($\text{today} - 180\text{d} \le \text{rel\_date} \le \text{today}$).
- **Language**: `ta` (Original Tamil).
- **Gate**: $\text{IMDb Votes} + \text{Letterboxd Votes} \ge 400$.
- **Vote Velocity Formula ($dv/dt$)**:
  $$\text{Velocity} = \frac{1.5 \times \text{Letterboxd Votes} + \text{IMDb Votes}}{\text{Age in Days} + 21}$$
  - **1.5x Multiplier on Letterboxd**: Letterboxd logs reflect active daily viewings by cinephiles rather than passive legacy votes.
  - **+21 Dampening Denominator**: Prevents asymptotes on Days 1–3 where a movie with 400 votes on Day 1 would yield an artificial velocity of 400/1 = 400, unfairly beating a theatrical hit with 60,000 votes on Day 14.
  - **Result**: Breakout hits (*Jailer 2*, *Dorothy*, *Baththa*) rise to ranks 1–3, while older releases naturally decelerate.

---

### 2. New in Theaters (`new_releases`)
- **Objective**: Track new theatrical releases available to watch right now.
- **Window**: Theatrical release within the last 90 days ($\text{today} - 90\text{d} \le \text{rel\_date} \le \text{today}$).
- **Language**: `ta` (Original Tamil).
- **Anti-Indie / Anti-Phantom Gate**:
  $$\text{IMDb Votes} \ge 400 \quad\text{OR}\quad \text{Letterboxd Votes} \ge 200$$
  - Every legitimate Indian theatrical or major OTT release crosses 400 IMDb votes during its opening weekend.
  - Micro-budget festival screenings with negligible audience footprint (e.g. 19 votes globally) are cleanly eliminated.
- **Ranking**: Strictly ordered by `release_date DESC` (newest first: *Drones*, *Jailer 2*, *All Pass*).

---

### 3. New on OTT (`new_ott`)
- **Objective**: Track newly arrived streaming and digital releases.
- **Source**: MDBList query `sort=releasedigital&sort_order=desc`.
- **Ranking Mechanism**:
  - MDBList internally indexes TMDB digital availability timestamps.
  - The lane preserves MDBList's server-side digital release sequence while enforcing our quality gate ($\text{votes} \ge 400$, $\text{runtime} \ge 85$, `language != 'en'`).
  - Movies that have only had theatrical releases (*Anbil Avan*) are excluded because MDBList's `releasedigital` index excludes them.

---

### 4. All-Time Masterpieces (`top_rated`)
- **Objective**: Hall-of-fame lane for the greatest regional films.
- **Gate**: Total verified votes $\ge 5,000$ and composite `rating_score >= 7.0`.
- **Ranking**: Sorted by `rating_score DESC`, then `votes DESC`.
- **Astroturf Resistance**: The source-count Bayesian shrinkage ensures that only films with multi-source consensus (*Baththa*, *Kadaisi Vivasayi*, *Anbe Sivam*, *Nayakan*, *Super Deluxe*) make the cut.

---

### 5. Popular Comedy (`comedy`)
- **Objective**: Comfort watch genre lane.
- **Gate**: Genre slug contains `comedy`, total votes $\ge 500$, `language != 'en'`.
- **Ranking**: Sorted by all-time `votes DESC` (*Chennai Express*, *Aavesham*, *Jailer*).

---

### 6. South Indian Blockbusters (`pan_india`)
- **Objective**: High-spectacle cross-industry cinema (Tamil, Telugu, Malayalam, Kannada).
- **Source**: MDBList List `76398`.
- **Gate**: Total votes $\ge 5,000$.
- **Ranking**: Sorted by all-time `votes DESC` (*RRR*, *Jai Bhim*, *Bāhubali*).

---

## 4. Serving Architecture: Carousel vs. "Show All" Grid

```
┌────────────────────────────────────────────────────────┐
│                   Cloudflare Worker                    │
├────────────────────────────────────────────────────────┤
│ GET /api/v1/dashboard/tamil                            │
│  -> Homepage view                                      │
│  -> Returns top 25 items per lane for carousel speed   │
│  -> Cached at edge (TTL: 12h)                          │
├────────────────────────────────────────────────────────┤
│ GET /api/v1/dashboard/tamil/lanes/:lane_id             │
│  -> "Show All" grid view                               │
│  -> Paginates full lane pool (100 items / page)        │
│  -> D1 SQL filters: genre, year, min_rating, sort_by   │
└────────────────────────────────────────────────────────┘
```

1. **Homepage Carousels** ([dashboard.ts#L33](file:///home/mukes/dev/movies/backend_revised/src/routes/dashboard.ts#L33)):
   - Serves the top 20–30 ranked items per lane.
   - Prevents DOM bloat and optimizes mobile bandwidth.
2. **"Show All" Paginated Grid** ([dashboard.ts#L58](file:///home/mukes/dev/movies/backend_revised/src/routes/dashboard.ts#L58)):
   - Retains the entire qualified pool in `lane_entries` (e.g. 500–1,000 titles).
   - Allows users to drill in, paginate with infinite scroll, and re-sort by `popular`, `rating`, `recent`, or `votes`.
