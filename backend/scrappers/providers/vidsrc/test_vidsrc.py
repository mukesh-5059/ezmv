import unittest
from unittest.mock import AsyncMock, MagicMock
from backend.scrappers.base import MediaItem, StreamSource
from backend.scrappers.providers.vidsrc.scraper import (
    VidSrcScraper,
    HLSExtractorService,
    StreamResult,
    build_embed_url,
    DEFAULT_BASE_DOMAINS,
    FIREFOX_PREFS,
    STUB_JS_PATTERNS,
)

class TestVidSrcScraper(unittest.TestCase):
    def test_build_embed_url(self):
        movie_url = build_embed_url("https://vidsrc.sh", "tt0133093", "movie")
        self.assertEqual(movie_url, "https://vidsrc.sh/embed/movie/tt0133093")

        tv_url = build_embed_url("https://vidsrc.sh", "tt0944947", "tv", season=2, episode=5)
        self.assertEqual(tv_url, "https://vidsrc.sh/embed/tv/tt0944947/2/5")

    def test_stream_result(self):
        res = StreamResult(
            success=True,
            m3u8_url="https://cdn.example.com/master.m3u8",
            headers={"Referer": "https://vidsrc.sh/"},
            elapsed_ms=1500
        )
        self.assertTrue(res.success)
        self.assertEqual(res.m3u8_url, "https://cdn.example.com/master.m3u8")
        self.assertEqual(res.headers.get("Referer"), "https://vidsrc.sh/")
        self.assertIn("m3u8_url", res.to_dict())

    def test_constants_configured(self):
        self.assertIn("https://vidsrc.sh", DEFAULT_BASE_DOMAINS)
        self.assertEqual(FIREFOX_PREFS["media.autoplay.default"], 0)
        self.assertIn("disable-devtool.js", STUB_JS_PATTERNS)

class TestVidSrcScraperAsync(unittest.IsolatedAsyncioTestCase):
    async def test_scrape_with_imdb_id(self):
        item = MediaItem(
            title="The Matrix",
            year=1999,
            imdb_id="tt0133093",
            media_type="movie"
        )
        mock_extractor = MagicMock(spec=HLSExtractorService)
        mock_extractor.extract_m3u8 = AsyncMock(
            return_value=StreamResult(
                success=True,
                m3u8_url="https://stream.example.com/master.m3u8",
                headers={"Referer": "https://cloudorchestranova.com/"},
                elapsed_ms=1400
            )
        )

        scraper = VidSrcScraper(extractor=mock_extractor)
        sources = await scraper.scrape(item)

        self.assertEqual(len(sources), 1)
        self.assertIsInstance(sources[0], StreamSource)
        self.assertEqual(sources[0].url, "https://stream.example.com/master.m3u8")
        self.assertEqual(sources[0].provider, "VidSrc (HLS)")
        self.assertEqual(sources[0].headers["Referer"], "https://cloudorchestranova.com/")

    async def test_scrape_missing_identifiers(self):
        item = MediaItem(title="Unknown", year=2020)
        scraper = VidSrcScraper()
        sources = await scraper.scrape(item)
        self.assertEqual(sources, [])

if __name__ == "__main__":
    unittest.main()
