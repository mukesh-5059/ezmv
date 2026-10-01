import unittest
from backend.scrappers.manager import format_stream_sources

class TestStreamProxy(unittest.TestCase):
    def test_format_vidsrc_proxied_url(self):
        raw_streams = [
            {
                "url": "https://example.com/stream/master.m3u8?token=xyz",
                "quality": "1080p",
                "provider": "VidSrc (1080p)",
                "headers": {
                    "Referer": "https://cloudorchestranova.com/",
                    "Origin": "https://cloudorchestranova.com"
                },
                "priority": 30
            }
        ]

        formatted = format_stream_sources(raw_streams, host="192.168.1.10")
        self.assertEqual(len(formatted), 1)
        item = formatted[0]
        self.assertEqual(item["type"], "hls")
        self.assertEqual(item["quality"], "1080p")
        self.assertEqual(item["provider"], "VidSrc (1080p)")
        self.assertTrue(item["url"].startswith("http://192.168.1.10:8888/proxy/hls/manifest.m3u8?"))
        self.assertIn("d=https%3A%2F%2Fexample.com%2Fstream%2Fmaster.m3u8%3Ftoken%3Dxyz", item["url"])
        self.assertIn("api_password=mediaflow_secret", item["url"])
        self.assertIn("h_referer=https%3A%2F%2Fcloudorchestranova.com%2F", item["url"])
        self.assertIn("h_origin=https%3A%2F%2Fcloudorchestranova.com", item["url"])

    def test_format_direct_mp4_unproxied(self):
        raw_streams = [
            {
                "url": "https://isaimini.example/movie.mp4",
                "quality": "720p",
                "provider": "Isaimini (720p)",
                "headers": {},
                "priority": 10
            }
        ]

        formatted = format_stream_sources(raw_streams, host="192.168.1.10")
        self.assertEqual(len(formatted), 1)
        item = formatted[0]
        self.assertEqual(item["type"], "direct")
        self.assertEqual(item["url"], "https://isaimini.example/movie.mp4")
