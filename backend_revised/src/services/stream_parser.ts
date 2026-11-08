import { StreamSource } from '../types';

export const LANGUAGE_MAP: Record<string, string> = {
  ta: 'Tamil',
  tam: 'Tamil',
  tamil: 'Tamil',
  te: 'Telugu',
  tel: 'Telugu',
  telugu: 'Telugu',
  hi: 'Hindi',
  hin: 'Hindi',
  hindi: 'Hindi',
  mal: 'Malayalam',
  ml: 'Malayalam',
  malayalam: 'Malayalam',
  kan: 'Kannada',
  kn: 'Kannada',
  kannada: 'Kannada',
  en: 'English',
  eng: 'English',
  english: 'English',
  bn: 'Bengali',
  ben: 'Bengali',
  bengali: 'Bengali',
  mr: 'Marathi',
  mar: 'Marathi',
  marathi: 'Marathi',
  pa: 'Punjabi',
  pan: 'Punjabi',
  punjabi: 'Punjabi',
  gu: 'Gujarati',
  guj: 'Gujarati',
  gujarati: 'Gujarati',
  fr: 'French',
  fre: 'French',
  fra: 'French',
  french: 'French',
  es: 'Spanish',
  spa: 'Spanish',
  spanish: 'Spanish',
  de: 'German',
  ger: 'German',
  deu: 'German',
  german: 'German',
  ja: 'Japanese',
  jap: 'Japanese',
  jpn: 'Japanese',
  japanese: 'Japanese',
  ko: 'Korean',
  kor: 'Korean',
  korean: 'Korean',
  zh: 'Chinese',
  chi: 'Chinese',
  zho: 'Chinese',
  chinese: 'Chinese',
  ru: 'Russian',
  rus: 'Russian',
  russian: 'Russian',
  it: 'Italian',
  ita: 'Italian',
  italian: 'Italian',
};

export function normalizeLanguage(langOrCode?: string): string | undefined {
  if (!langOrCode) return undefined;
  const clean = langOrCode.trim().toLowerCase();
  return LANGUAGE_MAP[clean] || (clean.charAt(0).toUpperCase() + clean.slice(1));
}

export const INDIAN_LANGUAGES = new Set([
  'Tamil',
  'Telugu',
  'Hindi',
  'Malayalam',
  'Kannada',
  'Bengali',
  'Marathi',
  'Punjabi',
  'Gujarati',
]);

export function isIndianLanguage(langOrCode?: string): boolean {
  if (!langOrCode) return false;
  const norm = normalizeLanguage(langOrCode);
  return norm ? INDIAN_LANGUAGES.has(norm) : false;
}

export function parseLanguages(text: string, defaultLanguage?: string): string[] {
  const normDefault = normalizeLanguage(defaultLanguage);
  if (!text) return normDefault ? [normDefault] : [];

  const tokens = text.toLowerCase().split(/[^a-z0-9]+/);
  const detected = new Set<string>();

  for (const token of tokens) {
    const lang = LANGUAGE_MAP[token];
    if (lang) detected.add(lang);
  }

  if (detected.size > 0) return Array.from(detected);
  return normDefault ? [normDefault] : [];
}

export function parseQuality(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes('2160') || lower.includes('4k') || lower.includes('uhd')) return '4K UHD';
  if (lower.includes('1080') || lower.includes('fhd')) return '1080p';
  if (lower.includes('720') || lower.includes('hd')) return '720p';
  if (lower.includes('480') || lower.includes('sd')) return '480p SD';
  return 'Auto';
}

export function extractFilename(raw: any): string | undefined {
  const hints = raw.behaviorHints || {};
  let filename = hints.filename as string | undefined;
  if (filename) return filename.split('|^|')[0].trim();

  if (raw.description) {
    const lines = (raw.description as string).split('\n');
    const fileLine = lines.find((l) => /\.(mkv|mp4|avi|webm)/i.test(l)) || lines[0];
    if (fileLine) {
      const cleaned = fileLine.replace(/^(\[[^\]]+\]\s*)+/, '').trim();
      if (cleaned.length > 5) return cleaned.split('|^|')[0].trim();
    }
  }

  const title = (raw.title || raw.name || '').replace(/\n/g, ' ').trim();
  return title ? title.split('|^|')[0].trim() : undefined;
}

export function formatSizeBytes(bytes?: number): string | undefined {
  if (!bytes || bytes <= 0) return undefined;
  const mb = bytes / (1024 * 1024);
  if (mb >= 1024) return `${(mb / 1024).toFixed(2)} GB`;
  return `${Math.round(mb)} MB`;
}

export function calculatePriority(
  provider: string,
  quality: string,
  languages?: string[],
  defaultLanguage?: string,
  host?: string,
  sizeBytes?: number,
  originalLanguage?: string
): number {
  let score = 100;
  const pLow = provider.toLowerCase();
  if (pLow === 'hdhub') score -= 70;
  else if (pLow === 'plaviohd') score -= 20;
  else if (pLow === 'penguplay') score -= 10;

  if (host) {
    const hLow = host.toLowerCase();
    if (
      hLow.includes('pixeldrain') ||
      hLow.includes('googleusercontent') ||
      hLow.includes('hubcloud') ||
      (hLow.includes('workers.dev') && !hLow.includes('notorrent'))
    ) {
      score -= 15;
    } else if (
      hLow.includes('notorrent') ||
      hLow.includes('vidvault') ||
      hLow.includes('streamtape') ||
      hLow.includes('dood')
    ) {
      score += 20;
    }
  }

  if (sizeBytes && sizeBytes > 0) {
    const gb = sizeBytes / (1024 * 1024 * 1024);
    if (gb <= 3.5) score -= 5;
    else if (gb > 25) score += 5;
  }

  const isIndian = isIndianLanguage(originalLanguage);
  const normOrig = normalizeLanguage(originalLanguage);
  const normDefault = normalizeLanguage(defaultLanguage);

  if (isIndian) {
    const hasTamil = languages?.some((l) => l.toLowerCase() === 'tamil');
    if (hasTamil) score -= 30;
    else if (normOrig && languages?.some((l) => l.toLowerCase() === normOrig.toLowerCase())) score -= 20;
    else if (normDefault && languages?.some((l) => l.toLowerCase() === normDefault.toLowerCase())) score -= 15;
  } else if (originalLanguage) {
    if (normOrig && languages?.some((l) => l.toLowerCase() === normOrig.toLowerCase())) score -= 30;
    else if (normDefault && languages?.some((l) => l.toLowerCase() === normDefault.toLowerCase())) score -= 15;
  } else {
    const hasTamil = languages?.some((l) => l.toLowerCase() === 'tamil');
    if (hasTamil) score -= 30;
    else if (normDefault && languages?.some((l) => l.toLowerCase() === normDefault.toLowerCase())) score -= 15;
  }

  if (quality === '1080p') score -= 20;
  else if (quality === '4K UHD') score -= 10;
  else if (quality === '720p') score -= 5;

  return score;
}

export function parseStreamItem(
  raw: any,
  provider: string,
  defaultLanguage?: string,
  originalLanguage?: string
): StreamSource | null {
  const url = raw.url;
  if (!url || typeof url !== 'string' || !url.startsWith('http')) return null;

  const filename = extractFilename(raw);
  const fullText = `${raw.name || ''} ${raw.description || ''} ${filename || ''}`;

  if (/donation|support the project|discord\.gg/i.test(fullText) && !raw.behaviorHints?.videoSize) return null;

  const quality = parseQuality(fullText);
  if (quality === '4K UHD') return null;

  const languages = parseLanguages(fullText, defaultLanguage || originalLanguage);

  const sizeBytes =
    typeof raw.behaviorHints?.videoSize === 'number' && raw.behaviorHints.videoSize > 0
      ? raw.behaviorHints.videoSize
      : undefined;

  let host: string | undefined;
  try {
    host = new URL(url).hostname;
  } catch {}

  const headers: Record<string, string> = {
    'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };
  if (raw.behaviorHints?.proxyHeaders?.request) Object.assign(headers, raw.behaviorHints.proxyHeaders.request);

  return {
    url,
    quality,
    filename,
    size_bytes: sizeBytes,
    formatted_size: formatSizeBytes(sizeBytes),
    priority: calculatePriority(provider, quality, languages, defaultLanguage, host, sizeBytes, originalLanguage),
    provider,
    host,
    languages: languages.length > 0 ? languages : undefined,
    headers,
  };
}
