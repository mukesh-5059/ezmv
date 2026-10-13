import unittest
from unittest.mock import AsyncMock, patch
from backend.models import LaneMoviesResponse, PaginatedMovieResponse, MovieSummary
from backend.routes.movies import get_dashboard, get_dashboard_lane, search_or_discover, get_list_items_endpoint

class TestPaginationAndLanes(unittest.TestCase):
    def test_response_models_sync_items_and_results(self):
        m = MovieSummary(tmdb_id=123, title="Test Movie")
        res1 = LaneMoviesResponse(items=[m], page=1, has_more=True, next_page=2)
        self.assertEqual(len(res1.items), 1)
        self.assertEqual(len(res1.results), 1)
        self.assertEqual(res1.results[0].tmdb_id, 123)

        res2 = PaginatedMovieResponse(results=[m], page=1, has_more=True, next_page=2)
        self.assertEqual(len(res2.items), 1)
        self.assertEqual(len(res2.results), 1)
        self.assertEqual(res2.items[0].tmdb_id, 123)

    def test_tamil_dashboard_lanes_split(self):
        async def run_test():
            fake_tmdb_movies = [{"id": 999, "title": "New Tamil Movie", "original_language": "ta"}]
            with patch("backend.routes.movies.tmdb_client.discover_movies", new=AsyncMock(return_value=fake_tmdb_movies)), \
                 patch("backend.routes.movies.catalog_service.get_lane_movies", return_value=[{"tmdb_id": 888, "title": "Trending Movie"}]):
                resp = await get_dashboard(language="ta")
                self.assertGreaterEqual(len(resp.lanes), 2)
                self.assertEqual(resp.lanes[0].id, "new")
                self.assertEqual(resp.lanes[0].title, "New Releases")
                self.assertEqual(resp.lanes[0].items[0].tmdb_id, 999)
                self.assertEqual(resp.lanes[1].id, "trending")
                self.assertEqual(resp.lanes[1].title, "Trending Tamil")
                self.assertEqual(resp.lanes[1].items[0].tmdb_id, 888)

        import asyncio
        asyncio.run(run_test())

    def test_dashboard_lane_new_releases(self):
        async def run_test():
            fake_tmdb_movies = [{"id": 101, "title": "New Movie 1", "original_language": "ta"}]
            with patch("backend.routes.movies.tmdb_client.discover_movies", new=AsyncMock(return_value=fake_tmdb_movies)) as mock_discover:
                resp = await get_dashboard_lane(lane_id="new", language="ta", page=1, limit=20)
                self.assertEqual(resp.id, "new")
                self.assertEqual(len(resp.items), 1)
                self.assertEqual(len(resp.results), 1)
                self.assertEqual(resp.items[0].tmdb_id, 101)
                mock_discover.assert_awaited_once_with(
                    language="ta",
                    genre=None,
                    year=None,
                    sort_by="primary_release_date.desc",
                    page=1,
                )

        import asyncio
        asyncio.run(run_test())

    def test_dashboard_lane_catalog_pagination_and_filter(self):
        async def run_test():
            fake_catalog_movies = [{"tmdb_id": 202, "title": "Trending Catalog Movie"}]
            with patch("backend.routes.movies.catalog_service.get_lane_movies", return_value=fake_catalog_movies), \
                 patch("backend.routes.movies.catalog_service.get_lane_count", return_value=45):
                resp = await get_dashboard_lane(lane_id="trending", language="ta", page=1, limit=20)
                self.assertEqual(resp.id, "trending")
                self.assertEqual(resp.page, 1)
                self.assertEqual(resp.total_pages, 3)
                self.assertFalse(resp.has_more)
                self.assertEqual(resp.items[0].tmdb_id, 202)
                self.assertEqual(resp.results[0].tmdb_id, 202)

            fake_filtered = [{"id": 303, "title": "Filtered TMDB Movie", "original_language": "ta"}]
            with patch("backend.routes.movies.tmdb_client.discover_movies", new=AsyncMock(return_value=fake_filtered)) as mock_discover:
                resp2 = await get_dashboard_lane(lane_id="trending", language="ta", page=2, limit=20, year=2024, genre=28)
                self.assertEqual(resp2.id, "trending")
                self.assertEqual(resp2.page, 2)
                self.assertEqual(resp2.items[0].tmdb_id, 303)
                mock_discover.assert_awaited_once_with(
                    language="ta",
                    genre=28,
                    year=2024,
                    sort_by="popularity.desc",
                    page=2,
                )

        import asyncio
        asyncio.run(run_test())

    def test_search_and_discover_pagination(self):
        async def run_test():
            fake_discover = [{"id": 404, "title": "Discovered Movie", "original_language": "ta"}]
            with patch("backend.routes.movies.tmdb_client.discover_movies", new=AsyncMock(return_value=fake_discover)):
                resp = await search_or_discover(language="ta", page=1)
                self.assertEqual(resp.page, 1)
                self.assertEqual(resp.items[0].tmdb_id, 404)
                self.assertEqual(resp.results[0].tmdb_id, 404)

        import asyncio
        asyncio.run(run_test())

    def test_list_items_pagination(self):
        async def run_test():
            fake_list_items = [MovieSummary(tmdb_id=505, title="List Movie")]
            with patch("backend.routes.movies.trakt_client.get_list_items", new=AsyncMock(return_value=fake_list_items)):
                resp = await get_list_items_endpoint(list_id="popular-tamil", page=1, limit=20)
                self.assertEqual(resp.page, 1)
                self.assertEqual(resp.items[0].tmdb_id, 505)
                self.assertEqual(resp.results[0].tmdb_id, 505)

        import asyncio
        asyncio.run(run_test())

    def test_filter_and_enrich_imdb(self):
        from backend.services.tmdb import tmdb_client
        async def run_test():
            raw = [
                {"id": 1, "title": "Has IMDb & 50+ Votes", "release_date": "2024-01-01"},
                {"id": 2, "title": "No IMDb", "release_date": "2024-01-01"},
                {"id": 3, "title": "Reality TV Show", "genre_ids": [10764], "release_date": "2024-01-01"},
                {"id": 4, "title": "Old Movie with <50 votes", "release_date": "2024-01-01"},
            ]
            async def fake_details(movie_id):
                if movie_id == 1:
                    return {"id": 1, "imdb_id": "tt1234567"}
                if movie_id == 3:
                    return {"id": 3, "imdb_id": "tt3333333", "genres": [{"id": 10764, "name": "Reality"}]}
                if movie_id == 4:
                    return {"id": 4, "imdb_id": "tt4444444"}
                return {"id": 2, "imdb_id": None}

            ratings_map = {
                "tt1234567": (8.5, 1200),
                "tt3333333": (6.0, 500),
                "tt4444444": (4.0, 15),
            }

            with patch.object(tmdb_client, "get_movie_details", side_effect=fake_details), \
                 patch("backend.services.tmdb.get_imdb_ratings_batch", return_value=ratings_map):
                res = await tmdb_client.filter_and_enrich_imdb(raw)
                self.assertEqual(len(res), 1)
                self.assertEqual(res[0]["id"], 1)
                self.assertEqual(res[0]["imdb_id"], "tt1234567")
                self.assertEqual(res[0]["vote_average"], 8.5)
                self.assertEqual(res[0]["vote_count"], 1200)

        import asyncio
        asyncio.run(run_test())

    def test_get_details_imdb_enrichment(self):
        from backend.routes.movies import get_details
        async def run_test():
            fake_det = {"id": 100, "title": "Film", "imdb_id": "tt9999999", "vote_average": 2.0, "vote_count": 3}
            with patch("backend.routes.movies.tmdb_client.get_movie_details", new=AsyncMock(return_value=fake_det)), \
                 patch("backend.services.imdb_ratings.get_imdb_rating", return_value=(9.1, 5000)):
                res = await get_details(tmdb_id=100, media_type="movie")
                self.assertEqual(res.tmdb_id, 100)
                self.assertEqual(res.imdb_id, "tt9999999")
                self.assertEqual(res.vote_average, 9.1)
                self.assertEqual(res.vote_count, 5000)

        import asyncio
        asyncio.run(run_test())

if __name__ == "__main__":
    unittest.main()
