import { Router } from 'express';
import { z } from 'zod';
import { env } from '../env';
import { requireAuth } from '../middleware/auth';
import { HttpError } from '../middleware/error';

/// OpenSubtitles proxy for the web player. Browsers can't call the
/// OpenSubtitles API directly (its CORS preflight rejects the Api-Key
/// header), and doing it here also keeps the account credentials off the
/// client.
const router = Router();
router.use(requireAuth);

const OS_BASE = 'https://api.opensubtitles.com/api/v1';

const osHeaders = (token?: string): Record<string, string> => ({
  'Api-Key': env.OPENSUBTITLES_API_KEY,
  'User-Agent': env.OPENSUBTITLES_USER_AGENT,
  Accept: 'application/json',
  'Content-Type': 'application/json',
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
});

/// fetch with a timeout; network failures become a 502 instead of a 500.
/// OpenSubtitles rate-limits (5 requests/second) and has the odd hiccup, so
/// a 429 or 5xx is retried once after a second.
async function upstream(url: string, init?: RequestInit): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    let res: Response;
    try {
      res = await fetch(url, { ...init, signal: AbortSignal.timeout(15_000) });
    } catch {
      throw new HttpError(502, 'SUBTITLES_UPSTREAM', 'OpenSubtitles is not responding');
    }
    if (attempt === 0 && (res.status === 429 || res.status >= 500)) {
      await new Promise((r) => setTimeout(r, 1100));
      continue;
    }
    return res;
  }
}

// Logging in raises the daily download quota. Kept per warm instance.
let session: { token: string; base: string; at: number } | null = null;
const SESSION_TTL_MS = 23 * 60 * 60 * 1000;

async function osSession(): Promise<{ token?: string; base: string }> {
  if (!env.OPENSUBTITLES_USERNAME || !env.OPENSUBTITLES_PASSWORD) {
    return { base: OS_BASE };
  }
  if (session && Date.now() - session.at < SESSION_TTL_MS) return session;
  const res = await upstream(`${OS_BASE}/login`, {
    method: 'POST',
    headers: osHeaders(),
    body: JSON.stringify({
      username: env.OPENSUBTITLES_USERNAME,
      password: env.OPENSUBTITLES_PASSWORD,
    }),
  });
  if (!res.ok) {
    // Fall back to anonymous downloads rather than failing outright.
    return { base: OS_BASE };
  }
  const body = (await res.json()) as { token?: string; base_url?: string };
  if (!body.token) return { base: OS_BASE };
  session = {
    token: body.token,
    base: body.base_url ? `https://${body.base_url}/api/v1` : OS_BASE,
    at: Date.now(),
  };
  return session;
}

const searchSchema = z.object({
  tmdbId: z.coerce.number().int().positive(),
  mediaType: z.enum(['movie', 'tv']),
  season: z.coerce.number().int().positive().optional(),
  episode: z.coerce.number().int().positive().optional(),
  lang: z.string().regex(/^[a-z]{2}(-[a-z]{2})?$/i).default('en'),
});

type OsFile = { file_id: number; file_name?: string };
type OsItem = {
  attributes: {
    language?: string;
    release?: string;
    download_count?: number;
    hearing_impaired?: boolean;
    files?: OsFile[];
  };
};

/// English (or `lang`) subtitle tracks for a title, most downloaded first.
router.get('/', async (req, res, next) => {
  try {
    const q = searchSchema.parse(req.query);
    const params = new URLSearchParams({ languages: q.lang.toLowerCase() });
    if (q.mediaType === 'movie') {
      params.set('tmdb_id', String(q.tmdbId));
      params.set('type', 'movie');
    } else {
      if (!q.season || !q.episode) {
        throw new HttpError(400, 'BAD_EPISODE', 'season and episode are required for tv');
      }
      params.set('parent_tmdb_id', String(q.tmdbId));
      params.set('season_number', String(q.season));
      params.set('episode_number', String(q.episode));
      params.set('type', 'episode');
    }
    params.set('order_by', 'download_count');
    // OpenSubtitles redirects unsorted queries to the sorted URL, and that
    // redirect hangs from some networks.
    params.sort();
    const { base } = await osSession();
    const r = await upstream(`${base}/subtitles?${params}`, { headers: osHeaders() });
    if (!r.ok) throw new HttpError(502, 'SUBTITLES_UPSTREAM', `OpenSubtitles search failed (${r.status})`);
    const body = (await r.json()) as { data?: OsItem[] };
    const items = (body.data ?? [])
      .map((d) => {
        const file = d.attributes.files?.[0];
        if (!file) return null;
        return {
          fileId: file.file_id,
          language: d.attributes.language ?? q.lang,
          release: d.attributes.release ?? file.file_name ?? 'Subtitles',
          downloads: d.attributes.download_count ?? 0,
          hearingImpaired: d.attributes.hearing_impaired ?? false,
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .sort((a, b) => b.downloads - a.downloads)
      .slice(0, 20);
    res.json({ items });
  } catch (e) {
    next(e);
  }
});

// Downloads count against the daily quota, so keep what we've fetched.
const fileCache = new Map<number, string>();
const FILE_CACHE_MAX = 200;

/// The subtitle file itself (SRT or VTT text) for a fileId from the search.
router.get('/file/:fileId', async (req, res, next) => {
  try {
    const fileId = z.coerce.number().int().positive().parse(req.params.fileId);
    let text = fileCache.get(fileId);
    if (text === undefined) {
      const { token, base } = await osSession();
      const r = await upstream(`${base}/download`, {
        method: 'POST',
        headers: osHeaders(token),
        body: JSON.stringify({ file_id: fileId }),
      });
      if (r.status === 406 || r.status === 429) {
        throw new HttpError(429, 'SUBTITLES_QUOTA', 'Daily subtitle download limit reached');
      }
      if (!r.ok) throw new HttpError(502, 'SUBTITLES_UPSTREAM', `OpenSubtitles download failed (${r.status})`);
      const { link } = (await r.json()) as { link?: string };
      if (!link) throw new HttpError(502, 'SUBTITLES_UPSTREAM', 'OpenSubtitles returned no link');
      const file = await upstream(link);
      if (!file.ok) throw new HttpError(502, 'SUBTITLES_UPSTREAM', `Subtitle file fetch failed (${file.status})`);
      text = await file.text();
      if (fileCache.size >= FILE_CACHE_MAX) {
        const oldest = fileCache.keys().next().value;
        if (oldest !== undefined) fileCache.delete(oldest);
      }
      fileCache.set(fileId, text);
    }
    res.type('text/plain; charset=utf-8').send(text);
  } catch (e) {
    next(e);
  }
});

export default router;
