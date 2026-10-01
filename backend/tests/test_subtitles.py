import unittest
from unittest.mock import AsyncMock, patch, MagicMock
from backend.services.subtitles import SubtitlesService, SubtitleTrack, SubtitleResponse

class TestSubtitlesService(unittest.IsolatedAsyncioTestCase):
    async def test_subtitles_parsing_and_sorting(self):
        service = SubtitlesService()
        mock_resp_data = {
            "subtitles": [
                {
                    "id": "1",
                    "lang": "spa",
                    "url": "https://subs.example.com/es.vtt",
                    "movieReleaseName": "Movie.Spanish"
                },
                {
                    "id": "2",
                    "lang": "eng",
                    "url": "https://subs.example.com/en.vtt",
                    "movieReleaseName": "Movie.English"
                },
                {
                    "id": "3",
                    "lang": "tam",
                    "url": "https://subs.example.com/ta.vtt",
                    "movieReleaseName": "Movie.Tamil"
                }
            ]
        }

        mock_session = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = mock_resp_data
        mock_session.get = AsyncMock(return_value=mock_response)

        with patch("backend.services.subtitles.get_session", return_value=mock_session), \
             patch.object(service, "_get_imdb_id", AsyncMock(return_value="tt1234567")):
            res = await service.get_subtitles(tmdb_id=123, media_type="movie")

            self.assertIsInstance(res, SubtitleResponse)
            self.assertEqual(res.imdb_id, "tt1234567")
            self.assertEqual(len(res.subtitles), 3)
            # English should be sorted first
            self.assertEqual(res.subtitles[0].code, "en")
            self.assertEqual(res.subtitles[0].language, "English")
            self.assertEqual(res.subtitles[0].url, "https://subs.example.com/en.vtt")

    async def test_subtitles_language_filter(self):
        service = SubtitlesService()
        mock_resp_data = {
            "subtitles": [
                {"id": "1", "lang": "spa", "url": "https://subs.example.com/es.vtt"},
                {"id": "2", "lang": "eng", "url": "https://subs.example.com/en.vtt"}
            ]
        }

        mock_session = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = mock_resp_data
        mock_session.get = AsyncMock(return_value=mock_response)

        with patch("backend.services.subtitles.get_session", return_value=mock_session), \
             patch.object(service, "_get_imdb_id", AsyncMock(return_value="tt1234567")):
            res = await service.get_subtitles(tmdb_id=123, media_type="movie", language="en")
            self.assertEqual(len(res.subtitles), 1)
            self.assertEqual(res.subtitles[0].code, "en")

if __name__ == "__main__":
    unittest.main()
