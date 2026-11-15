// router.js — Dynamic source and batch router for ezmvSources

function routeMedia(media, config) {
  var genres = (media && media.genres) || [];
  var lang = (media && media.originalLanguage || '').toLowerCase();
  var mediaType = (media && media.mediaType || 'movie').toLowerCase();

  var isAnime = genres.some(function(g) {
    var s = String(g).toLowerCase();
    return s === 'anime' || s === 'animation';
  }) && (lang === 'ja' || genres.some(function(g) { return String(g).toLowerCase() === 'anime'; }) || !lang);

  function matches(source) {
    if (!source || source.enabled === false) return false;
    var m = source.match || {};
    if (m.media_types && m.media_types.length) {
      if (m.media_types.indexOf(mediaType) === -1) return false;
    }
    if (m.genres && m.genres.length) {
      var genreMatch = m.genres.some(function(mg) {
        if (mg === 'anime' && isAnime) return true;
        return genres.some(function(g) { return String(g).toLowerCase() === mg.toLowerCase(); });
      });
      if (!genreMatch) return false;
    }
    if (m.original_languages && m.original_languages.length) {
      if (!isAnime && (!lang || m.original_languages.indexOf(lang) === -1)) return false;
    }
    return true;
  }

  var addons = (config.stremio_addons || []).filter(matches);
  var extractors = (config.js_extractors || []).filter(matches);

  var batchMap = {};
  function addSource(s, type) {
    var b = s.batch || s.priority || 1;
    if (!batchMap[b]) {
      batchMap[b] = { batchNumber: b, stremio_addons: [], js_extractors: [] };
    }
    if (type === 'addon') batchMap[b].stremio_addons.push(s);
    else batchMap[b].js_extractors.push(s);
  }

  addons.forEach(function(s) { addSource(s, 'addon'); });
  extractors.forEach(function(s) { addSource(s, 'extractor'); });

  var batchNums = Object.keys(batchMap).map(Number).sort(function(a, b) { return a - b; });
  return batchNums.map(function(num) {
    var b = batchMap[num];
    b.stremio_addons.sort(function(a, b) { return (a.priority || 10) - (b.priority || 10); });
    b.js_extractors.sort(function(a, b) { return (a.priority || 10) - (b.priority || 10); });
    return b;
  });
}
