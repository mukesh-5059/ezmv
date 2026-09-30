import unittest
from unittest.mock import AsyncMock, MagicMock, patch
from backend.scrappers.base import MediaItem, StreamSource
from backend.scrappers.providers.vidsrc.scraper import (
    VidSrcScraper,
    HLSExtractorService,
    StreamResult,
    build_embed_url,
    get_vidsrc_config,
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

    def test_constants_and_config(self):
        with patch("backend.scrappers.providers.vidsrc.scraper.CONFIG_PATH") as mock_path:
            mock_path.exists.return_value = False
            primary, domains = get_vidsrc_config()
            self.assertIsNone(primary)
            self.assertEqual(domains, [])

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

        with patch("backend.scrappers.providers.vidsrc.scraper.get_vidsrc_config", return_value=("https://vidsrc.sh", ["https://vidsrc.sh"])):
            scraper = VidSrcScraper(extractor=mock_extractor)
            sources = await scraper.scrape(item)

        self.assertEqual(len(sources), 1)
        self.assertIsInstance(sources[0], StreamSource)
        self.assertEqual(sources[0].url, "https://stream.example.com/master.m3u8")
        self.assertEqual(sources[0].provider, "VidSrc (1080p)")
        self.assertEqual(sources[0].quality, "1080p")
        self.assertEqual(sources[0].headers["Referer"], "https://cloudorchestranova.com/")

    async def test_scrape_missing_domain_aborts(self):
        item = MediaItem(title="The Matrix", year=1999, imdb_id="tt0133093", media_type="movie")
        with patch("backend.scrappers.providers.vidsrc.scraper.get_vidsrc_config", return_value=(None, [])):
            scraper = VidSrcScraper()
            sources = await scraper.scrape(item)
            self.assertEqual(sources, [])

    async def test_scrape_missing_identifiers(self):
        item = MediaItem(title="Unknown", year=2020)
        scraper = VidSrcScraper()
        sources = await scraper.scrape(item)
        self.assertEqual(sources, [])

if __name__ == "__main__":
    unittest.main()
