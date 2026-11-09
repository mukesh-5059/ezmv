import leoProfanity from 'leo-profanity';

// Initialize dictionary once when the isolate spins up
leoProfanity.loadDictionary('en');

// Add domain-specific NSFW terms common in user-created spam lists
leoProfanity.add(['onlyfans', 'xxx']);

// Whitelist legitimate cinema terms that could trigger false positives on movie lists
leoProfanity.remove([
  'snatch',
  'bastard',
  'bastards',
  'hell',
  'damn',
]);

/**
 * Returns true if the text contains profane or explicit NSFW terms.
 */
export function isProfane(text?: string | null): boolean {
  if (!text || typeof text !== 'string') return false;
  return leoProfanity.check(text);
}
