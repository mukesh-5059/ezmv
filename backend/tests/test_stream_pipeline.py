import unittest
from backend.scrappers.base import MediaItem
from backend.scrappers.providers.stremio import is_title_match, parse_stremio_stream
from backend.services.cache_db import (
    init_cache_db,
    save_cached_streams,
    get_cached_streams,
    delete_cached_streams,
)

class TestStreamPipeline(unittest.TestCase):
    def setUp(self):
        init_cache_db()
        self.leo_media = MediaItem(
            title="Leo",
            year=2023,
            media_type="movie",
            tmdb_id=626392,
            imdb_id="tt15654328",
            original_language="ta",
            runtime_minutes=164,
        )

    def test_title_guard_filters_false_positives(self):
        # Legitimate matches
        self.assertTrue(is_title_match(self.leo_media, "Leo.(2023).1080p.HQ.NF.WEB-DL.x264.mkv"))
        self.assertTrue(is_title_match(self.leo_media, "LEO.2023.HQ.1080p.WEB-DL.Hindi.DDP5.1-Tamil.ESub.x264-HDHub4u.Tv.mkv"))
        self.assertTrue(is_title_match(self.leo_media, "Leo.2023.Tamil.1080p.mp4"))

        # Upstream WordPress keyword search leaks that MUST be rejected
        self.assertFalse(is_title_match(self.leo_media, "Good.Luck.To.You,.Leo.Grande.2022.1080p.BluRay.Hindi.AMZN.English.ESubs.mkv"))
        self.assertFalse(is_title_match(self.leo_media, "Leo Da Vinci Mission Mona Lisa 2018 Hindi ORG Dual Audio 720p BluRay ESub.mkv"))

    def test_stream_metadata_parsing_and_bitrate(self):
        raw_stream = {
            "name": "HdHub\nVM 1080p",
            "description": "[PixelDrain] [💾 6.67 GB] LEO.2023.HQ.1080p.WEB-DL.Hindi.DDP5.1-Tamil.ESub.x264-HDHub4u.Tv.mkv\nHindi\npixeldrain | HdHub",
            "url": "https://pixeldrain.dev/api/file/YN5iJo6h?download",
            "behaviorHints": {
                "videoSize": 7161857966,
                "filename": "LEO.2023.HQ.1080p.WEB-DL.Hindi.DDP5.1-Tamil.ESub.x264-HDHub4u.Tv.mkv"
            }
        }
        parsed = parse_stremio_stream(raw_stream, "HdHub", self.leo_media)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.quality, "1080p")
        self.assertIn("Tamil", parsed.languages)
        self.assertIn("Hindi", parsed.languages)
        self.assertEqual(parsed.host, "PixelDrain")
        self.assertEqual(parsed.source, "HDHub4u")
        self.assertEqual(parsed.formatted_size, "6.67 GB")
        # Bitrate calculated: 6830 MB * 8 * 1024 / (164 * 60) ≈ 5686 kbps ≈ 5.7 Mbps
        self.assertIsNotNone(parsed.bitrate_kbps)
        self.assertGreater(parsed.bitrate_kbps, 4000)
        self.assertTrue("Mbps" in (parsed.bitrate_str or ""))
        # Tamil is present on a Tamil title, priority should be high (<= 20)
        self.assertLessEqual(parsed.priority, 20)

    def test_hindi_dub_priority_penalty(self):
        raw_hindi_only = {
            "name": "HdHub 1080p",
            "description": "[PixelDrain] [💾 2.5 GB] LEO.2023.1080p.WEB-DL.Hindi.x264-HDHub4u.Tv.mkv\nHindi\npixeldrain | HdHub",
            "url": "https://pixeldrain.dev/api/file/test?download",
            "behaviorHints": {
                "videoSize": 2684354560,
                "filename": "LEO.2023.1080p.WEB-DL.Hindi.x264-HDHub4u.Tv.mkv"
            }
        }
        parsed = parse_stremio_stream(raw_hindi_only, "HdHub", self.leo_media)
        self.assertIsNotNone(parsed)
        self.assertIn("Hindi", parsed.languages)
        self.assertNotIn("Tamil", parsed.languages)
        # Should be penalized since original_language is Tamil
        self.assertGreaterEqual(parsed.priority, 80)

    def test_cache_roundtrip_with_rich_metadata(self):
        delete_cached_streams(tmdb_id=999999)
        test_streams = [{
            "url": "https://test.host/stream.mp4",
            "quality": "1080p",
            "provider": "HdHub",
            "scraper_id": "hdhub",
            "headers": {"User-Agent": "TestUA"},
            "priority": 10,
            "size_mb": 3400.0,
            "formatted_size": "3.4 GB",
            "bitrate_kbps": 2800,
            "bitrate_str": "2.8 Mbps",
            "languages": ["Tamil", "Hindi"],
            "source": "HDHub4u",
            "host": "PixelDrain",
            "filename": "Test.2023.mkv",
            "ttl": 3600,
        }]
        save_cached_streams(tmdb_id=999999, streams=test_streams)
        cached = get_cached_streams(tmdb_id=999999)
        self.assertEqual(len(cached), 1)
        item = cached[0]
        self.assertEqual(item["quality"], "1080p")
        self.assertEqual(item["languages"], ["Tamil", "Hindi"])
        self.assertEqual(item["size_mb"], 3400.0)
        self.assertEqual(item["formatted_size"], "3.4 GB")
        self.assertEqual(item["bitrate_kbps"], 2800)
        self.assertEqual(item["bitrate_str"], "2.8 Mbps")
        self.assertEqual(item["source"], "HDHub4u")
        self.assertEqual(item["host"], "PixelDrain")
        self.assertEqual(item["filename"], "Test.2023.mkv")
        delete_cached_streams(tmdb_id=999999)

if __name__ == "__main__":
    unittest.main()
