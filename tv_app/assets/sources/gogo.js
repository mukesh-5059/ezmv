// AniGoGo — anime source for EzMV (animex.one API)

var SOURCE_ID = (typeof __SOURCE_ID !== 'undefined' && __SOURCE_ID)
  ? String(__SOURCE_ID) : 'gogo';

var SITE = 'https://animex.one';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
  + '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

async function _req(url, options) {
  options = options || {};
  var headers = Object.assign({
    'User-Agent': UA,
    'Origin': SITE,
    'Referer': SITE + '/'
  }, options.headers || {});

  var fetchOpts = {
    method: options.method || 'GET',
    headers: headers
  };

  if (options.data != null) {
    fetchOpts.body = typeof options.data === 'string' ? options.data : JSON.stringify(options.data);
  } else if (options.body != null) {
    fetchOpts.body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
  }

  var res = await fetch(url, fetchOpts);
  var body = (res && res.body) != null ? res.body : '';
  if (typeof body === 'string') {
    try {
      return JSON.parse(body);
    } catch (e) {
      return body;
    }
  }
  return body;
}

function getInfo() {
  return {
    id: SOURCE_ID,
    name: 'AniGoGo',
    lang: 'en',
    baseUrl: SITE,
    logo: 'https://anilist.co/img/icons/apple-touch-icon.png',
    type: 'anime',
    version: '1.0.0'
  };
}

async function latest(page) {
  var p = page || 1;
  var res = await _req('https://graphql.animex.one/api/recent?page=' + p);
  var results = (res && res.results) || [];
  return results.map(function (item) {
    var title = item.titleEnglish || item.titleRomaji || item.titleNative || '';
    var cover = (item.coverImage && (item.coverImage.extraLarge || item.coverImage.large)) || '';
    return {
      id: item.id.toString(),
      title: title,
      url: item.id.toString(),
      cover: cover
    };
  });
}

async function search(kw, page) {
  console.log('[AniGoGo][search] Searching keyword="' + kw + '"');
  var query = `
    query FastSearch($query: String, $limit: Int) {
      catalogAnime(filter: { query: $query }, limit: $limit) {
        items {
          id
          anilistId
          titleEnglish
          titleRomaji
          coverImage
        }
      }
    }
  `;
  var res = await _req('https://graphql.animex.one/graphql', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    data: {
      query: query,
      variables: {
        query: kw,
        limit: 15
      }
    }
  });

  var items = (res && res.data && res.data.catalogAnime && res.data.catalogAnime.items) || [];
  console.log('[AniGoGo][search] Found ' + items.length + ' item(s)');
  return items.map(function (item) {
    var title = item.titleEnglish || item.titleRomaji || item.id || 'N/A';
    var coverObj = typeof item.coverImage === 'string' ? JSON.parse(item.coverImage || '{}') : (item.coverImage || {});
    var cover = coverObj.extraLarge || coverObj.large || coverObj.medium || '';
    return {
      id: item.id.toString(),
      title: title,
      url: item.id.toString(),
      cover: cover
    };
  });
}

async function getDetail(url) {
  var animeId = String(url);
  console.log('[AniGoGo][getDetail] Loading details for animeId="' + animeId + '"');
  var title = animeId;
  var cover = '';
  var desc = '';

  try {
    var query = `
      query GetAnime($id: String!) {
        anime(id: $id) {
          id
          titleEnglish
          titleRomaji
          coverImage
          description
        }
      }
    `;
    var infoRes = await _req('https://graphql.animex.one/graphql', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      data: {
        query: query,
        variables: { id: animeId }
      }
    });
    var item = infoRes && infoRes.data && infoRes.data.anime;
    if (item) {
      title = item.titleEnglish || item.titleRomaji || animeId;
      var coverObj = typeof item.coverImage === 'string' ? JSON.parse(item.coverImage || '{}') : (item.coverImage || {});
      cover = coverObj.extraLarge || coverObj.large || coverObj.medium || '';
      desc = item.description || '';
    }
  } catch (e) {
    console.warn('[AniGoGo][getDetail] GraphQL anime query error: ' + (e && e.message || e));
  }

  var episodes = [];
  try {
    var epRes = await _req('https://pp.animex.one/rest/api/episodes?id=' + encodeURIComponent(animeId));
    if (Array.isArray(epRes) && epRes.length > 0) {
      episodes = epRes.map(function (ep) {
        var epNum = ep.number;
        var epTitle = (ep.titles && (ep.titles.en || ep.titles.x_jat || ep.titles.ja)) || ('Episode ' + epNum);
        return {
          id: animeId + ';' + epNum,
          number: epNum,
          title: 'Ep ' + epNum + ': ' + epTitle,
          url: animeId + ';' + epNum
        };
      });
    }
  } catch (e) {
    console.warn('[AniGoGo][getDetail] Episode fetch error: ' + (e && e.message || e));
  }
  console.log('[AniGoGo][getDetail] Found ' + episodes.length + ' episode(s)');

  if (episodes.length === 0) {
    episodes = [
      {
        id: animeId + ';1',
        number: 1,
        title: 'Episode 1',
        url: animeId + ';1'
      }
    ];
  }

  return {
    id: animeId,
    title: title,
    cover: cover,
    description: desc,
    type: 'anime',
    sourceId: SOURCE_ID,
    episodes: episodes
  };
}

async function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(';');
  var animeId = parts[0];
  var epNum = parts[1] || '1';
  console.log('[AniGoGo][getVideoSources] Fetching sources for animeId="' + animeId + '" ep=' + epNum);

  var providerId = 'nero';
  try {
    var serverRes = await _req('https://pp.animex.one/rest/api/servers?id=' + encodeURIComponent(animeId) + '&epNum=' + encodeURIComponent(epNum));
    if (serverRes && serverRes.subProviders && serverRes.subProviders.length > 0) {
      var defaultProv = serverRes.subProviders.find(function (p) { return p.default; });
      providerId = defaultProv ? defaultProv.id : serverRes.subProviders[0].id;
    }
  } catch (e) {
    console.warn('[AniGoGo][getVideoSources] Servers fetch error: ' + (e && e.message || e));
  }
  console.log('[AniGoGo][getVideoSources] Selected providerId="' + providerId + '"');

  var sourcesRes = await _req('https://pp.animex.one/rest/api/sources?id=' + encodeURIComponent(animeId) +
    '&epNum=' + encodeURIComponent(epNum) + '&type=sub&providerId=' + encodeURIComponent(providerId));

  var sources = (sourcesRes && sourcesRes.sources) || [];
  var streamUrl = '';
  if (sources.length > 0) {
    streamUrl = sources[0].url || '';
  }

  var subtitles = ((sourcesRes && sourcesRes.tracks) || [])
    .filter(function (t) { return t.url; })
    .map(function (t) {
      return {
        title: t.label || t.lang || 'Subtitle',
        url: t.url
      };
    });

  var reqHeaders = (sourcesRes && sourcesRes.headers) || {
    Referer: 'https://animex.one/'
  };

  if (!streamUrl) {
    console.warn('[AniGoGo][getVideoSources] No streamUrl resolved from provider ' + providerId);
    return [];
  }
  console.log('[AniGoGo][getVideoSources] Resolved stream URL: ' + streamUrl);

  return [{
    url: streamUrl,
    quality: 'Auto',
    headers: reqHeaders,
    subtitles: subtitles
  }];
}

// Aliases for backward compatibility
var detail = getDetail;
var watch = getVideoSources;
var __gogo = { search: search, detail: getDetail, watch: getVideoSources };

async function scrape(media) {
  try {
    var rawTitle = (media && media.title) || '';
    var title = rawTitle
      .replace(/\s+s\d+e\d+.*$/i, '')
      .replace(/\s+season\s*\d+.*$/i, '')
      .trim() || rawTitle;
    var episode = (media && media.episode) || 1;
    console.log('[AniGoGo][scrape] Starting scrape for title="' + title + '" ep=' + episode);
    if (!title) {
      console.warn('[AniGoGo][scrape] Title is empty');
      return [];
    }

    var searchResults = await search(title, 1);
    if (!searchResults || !searchResults.length) {
      console.warn('[AniGoGo][scrape] 0 search results for "' + title + '"');
      return [];
    }

    var card = searchResults[0];
    var animeId = card.url || card.id;
    console.log('[AniGoGo][scrape] Top matched animeId="' + animeId + '" (' + (card.title || '') + ')');
    var itemDetail = await getDetail(animeId);
    var episodes = (itemDetail && itemDetail.episodes) || [];
    if (!episodes.length) {
      console.warn('[AniGoGo][scrape] 0 episodes found in details for ' + animeId);
      return [];
    }

    var epTarget = null;
    for (var i = 0; i < episodes.length; i++) {
      var ep = episodes[i];
      if (ep.number == episode || (ep.id && String(ep.id).endsWith(';' + episode))) {
        epTarget = ep;
        break;
      }
    }
    if (!epTarget) {
      console.log('[AniGoGo][scrape] Episode ' + episode + ' not matched exactly; defaulting to first episode');
      epTarget = episodes[0];
    }
    console.log('[AniGoGo][scrape] Target episode: number=' + epTarget.number + ' id=' + epTarget.id);

    var epUrl = epTarget.url || epTarget.id;
    var sources = await getVideoSources(epUrl);
    console.log('[AniGoGo][scrape] Extracted ' + (sources ? sources.length : 0) + ' stream(s)');
    return sources || [];
  } catch (e) {
    console.error('[AniGoGo][scrape] Error during scrape: ' + (e && e.stack || e));
    return [];
  }
}
