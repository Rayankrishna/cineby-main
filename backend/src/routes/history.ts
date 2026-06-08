import { Router } from 'express';
import { prisma } from '../db';
import { requireAuth } from '../middleware/auth';
import {
  getOneHistoryQuerySchema,
  listHistoryQuerySchema,
  upsertHistorySchema,
} from '../schemas/history';
import { HttpError } from '../middleware/error';

const router = Router();
router.use(requireAuth);

const COMPLETED_RATIO = 0.9;
// Per-user retention cap. After each save we delete history rows past the
// newest N. Reduces row growth and keeps queries fast — Continue Watching
// and full history both read from this table.
const HISTORY_KEEP_LATEST = 10;

/// Delete all history rows for a user past the newest [HISTORY_KEEP_LATEST].
/// Fire-and-forget — callers should not await this on the hot path.
async function trimHistory(userId: string) {
  try {
    const keep = await prisma.watchHistoryItem.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
      take: HISTORY_KEEP_LATEST,
      select: { id: true },
    });
    if (keep.length < HISTORY_KEEP_LATEST) return;
    await prisma.watchHistoryItem.deleteMany({
      where: {
        userId,
        id: { notIn: keep.map((k) => k.id) },
      },
    });
  } catch (_) {
    // Best-effort. Don't surface trim errors to the user.
  }
}

router.post('/', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const data = upsertHistorySchema.parse(req.body);
    const season = data.mediaType === 'tv' ? data.seasonNumber ?? 0 : null;
    const episode = data.mediaType === 'tv' ? data.episodeNumber ?? 0 : null;
    const completed =
      data.durationSeconds != null && data.durationSeconds > 0
        ? data.progressSeconds / data.durationSeconds >= COMPLETED_RATIO
        : false;

    // Prisma's compound-unique `upsert` cannot accept `null` for any field
    // in the key — and movies always have `seasonNumber = null` and
    // `episodeNumber = null`. Use findFirst + update/create instead.
    const existing = await prisma.watchHistoryItem.findFirst({
      where: {
        userId,
        tmdbId: data.tmdbId,
        mediaType: data.mediaType,
        seasonNumber: season,
        episodeNumber: episode,
      },
    });

    const item = existing
      ? await prisma.watchHistoryItem.update({
          where: { id: existing.id },
          data: {
            progressSeconds: data.progressSeconds,
            durationSeconds: data.durationSeconds,
            completed,
            title: data.title,
            posterPath: data.posterPath,
            backdropPath: data.backdropPath,
            watchedAt: new Date(),
          },
        })
      : await prisma.watchHistoryItem.create({
          data: {
            userId,
            tmdbId: data.tmdbId,
            mediaType: data.mediaType,
            seasonNumber: season,
            episodeNumber: episode,
            progressSeconds: data.progressSeconds,
            durationSeconds: data.durationSeconds,
            completed,
            title: data.title,
            posterPath: data.posterPath,
            backdropPath: data.backdropPath,
          },
        });

    // Reply first, then trim in the background — keeps the upsert hot path
    // snappy. If the trim fails it's logged inside and silently swallowed.
    res.status(200).json(item);
    trimHistory(userId);
  } catch (e) {
    next(e);
  }
});

router.get('/', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const { limit, mediaType } = listHistoryQuerySchema.parse(req.query);
    const raw = await prisma.watchHistoryItem.findMany({
      where: { userId, ...(mediaType ? { mediaType } : {}) },
      orderBy: { updatedAt: 'desc' },
      take: 500,
    });
    const seen = new Set<string>();
    const items: typeof raw = [];
    for (const it of raw) {
      const key = `${it.mediaType}:${it.tmdbId}`;
      if (seen.has(key)) continue;
      seen.add(key);
      items.push(it);
      if (items.length >= limit) break;
    }
    res.json({ items, nextCursor: null });
  } catch (e) {
    next(e);
  }
});

router.get('/continue-watching', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const items = await prisma.watchHistoryItem.findMany({
      where: { userId, completed: false, progressSeconds: { gt: 30 } },
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
    const seenShows = new Set<string>();
    const dedup: typeof items = [];
    for (const it of items) {
      const key = `${it.mediaType}:${it.tmdbId}`;
      if (seenShows.has(key)) continue;
      seenShows.add(key);
      dedup.push(it);
      if (dedup.length >= 20) break;
    }
    res.json({ items: dedup });
  } catch (e) {
    next(e);
  }
});

router.get('/:tmdbId', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const tmdbId = Number(req.params.tmdbId);
    if (!Number.isFinite(tmdbId)) throw new HttpError(400, 'BAD_ID', 'Invalid tmdbId');
    const q = getOneHistoryQuerySchema.parse(req.query);

    // TV without explicit season/episode → return the latest episode watched.
    if (q.mediaType === 'tv' && (q.season == null || q.episode == null)) {
      const item = await prisma.watchHistoryItem.findFirst({
        where: { userId, tmdbId, mediaType: 'tv' },
        orderBy: { updatedAt: 'desc' },
      });
      return res.json({ item });
    }

    const season = q.mediaType === 'tv' ? q.season ?? 0 : null;
    const episode = q.mediaType === 'tv' ? q.episode ?? 0 : null;
    // Same reason as the POST handler — findUnique on the compound key
    // refuses null fields. findFirst handles nullable values correctly.
    const item = await prisma.watchHistoryItem.findFirst({
      where: {
        userId,
        tmdbId,
        mediaType: q.mediaType,
        seasonNumber: season,
        episodeNumber: episode,
      },
    });
    res.json({ item });
  } catch (e) {
    next(e);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const id = req.params.id;
    if (!id) throw new HttpError(400, 'BAD_ID', 'Missing id');
    const result = await prisma.watchHistoryItem.deleteMany({ where: { id, userId } });
    if (result.count === 0) throw new HttpError(404, 'NOT_FOUND', 'Entry not found');
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

router.delete('/', async (req, res, next) => {
  try {
    const userId = req.userId!;
    await prisma.watchHistoryItem.deleteMany({ where: { userId } });
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
