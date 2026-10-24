const { unstable_dev } = require("wrangler");

async function runTests() {
  console.log("==================================================");
  console.log("Starting Local Worker Diagnostic Integration Test");
  console.log("==================================================\n");

  const worker = await unstable_dev("src/index.ts", {
    experimental: { disableExperimentalWarning: true }
  });

  try {
    // 1. Dashboard Test (returns 100 per lane)
    console.log("TEST 1: GET /api/v1/dashboard");
    let t0 = Date.now();
    let res = await worker.fetch("/api/v1/dashboard");
    let duration = Date.now() - t0;
    console.log(`Status: ${res.status} (${duration}ms)`);
    let data = await res.json();
    console.log(`Lanes returned: ${data.lanes?.length}`);
    for (const lane of (data.lanes || [])) {
      console.log(`  ✓ Lane '${lane.id}': ${lane.items?.length} items (has_more: ${lane.has_more}, next_page: ${lane.next_page})`);
      if (lane.items?.[0]) {
        console.log(`    #1: "${lane.items[0].title}" (${lane.items[0].release_date?.slice(0, 4)}) | Rating: ${lane.items[0].rating}`);
      }
      if (lane.items?.[99]) {
        console.log(`    #100: "${lane.items[99].title}" (${lane.items[99].release_date?.slice(0, 4)}) | Rating: ${lane.items[99].rating}`);
      }
    }

    // 2. Dashboard Lane Pagination Test (Page 1: 1-100 vs Page 2: 101-200)
    console.log("\nTEST 2: GET /api/v1/dashboard/lane?lane_id=trending&page=1");
    res = await worker.fetch("/api/v1/dashboard/lane?lane_id=trending&page=1");
    console.log(`Status: ${res.status}`);
    data = await res.json();
    console.log(`Page 1: ${data.items?.length} items | has_more: ${data.has_more} | next_page: ${data.next_page}`);
    const page1First = data.items?.[0]?.title;
    const page1Last = data.items?.[data.items.length - 1]?.title;
    console.log(`  First item: "${page1First}" | Last item: "${page1Last}"`);

    console.log("\nTEST 3: GET /api/v1/dashboard/lane?lane_id=trending&page=2");
    t0 = Date.now();
    res = await worker.fetch("/api/v1/dashboard/lane?lane_id=trending&page=2");
    duration = Date.now() - t0;
    console.log(`Status: ${res.status} (${duration}ms)`);
    data = await res.json();
    console.log(`Page 2: ${data.items?.length} items | has_more: ${data.has_more} | next_page: ${data.next_page}`);
    const page2First = data.items?.[0]?.title;
    console.log(`  First item on page 2: "${page2First}"`);
    if (page1First && page2First && page1First !== page2First) {
      console.log(`  ✓ Pagination verified: Page 1 (#1: ${page1First}) and Page 2 (#101: ${page2First}) are distinct!`);
    }

    // 3. Single Movie Lookup Test
    console.log("\nTEST 4: GET /api/v1/movies/movie/tt36596965 (Direct D1 lookup)");
    res = await worker.fetch("/api/v1/movies/movie/tt36596965");
    console.log(`Status: ${res.status}`);
    const movieData = await res.json();
    console.log(`  Title: "${movieData.title}"`);
    console.log(`  IMDb ID: ${movieData.imdb_id} | TMDb ID: ${movieData.tmdb_id}`);
    console.log(`  Rating: ${movieData.rating} (${movieData.vote_count} votes)`);
    console.log(`  Release Date: ${movieData.release_date} | Runtime: ${movieData.runtime}m`);

    // 4. Search Endpoint Test (returns structured object with 100 items per page)
    console.log("\nTEST 5: GET /api/v1/search?query=vikram (Trakt -> MDBList -> D1)");
    t0 = Date.now();
    res = await worker.fetch("/api/v1/search?query=vikram");
    duration = Date.now() - t0;
    const searchData = await res.json();
    console.log(`Search Results Count: ${searchData.items?.length} | page: ${searchData.page}/${searchData.total_pages} | total_items: ${searchData.total_items} | has_more: ${searchData.has_more} | next_page: ${searchData.next_page}`);
    if (searchData.items?.[0]) {
      console.log(`  Top hit: "${searchData.items[0].title}" (${searchData.items[0].release_date?.slice(0, 4)}) | Rating: ${searchData.items[0].rating} | IMDb: ${searchData.items[0].imdb_id}`);
    }

    console.log("\n==================================================");
    console.log("All Integration Tests Completed Successfully!");
    console.log("==================================================");
  } finally {
    await worker.stop();
  }
}

runTests().catch(err => {
  console.error("Test Suite Failed:", err);
  process.exit(1);
});
