import { Router } from 'express';
import { prisma } from '../db';
import { requireAuth } from '../middleware/auth';
import {
  addWatchlistSchema,
  containsQuerySchema,
  watchlistQuerySchema,
} from '../schemas/watchlist';
import { HttpError } from '../middleware/error';

const router = Router();
router.use(requireAuth);

router.post('/', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const data = addWatchlistSchema.parse(req.body);
    const item = await prisma.watchlistItem.upsert({
      where: {
        userId_tmdbId_mediaType: {
          userId,
          tmdbId: data.tmdbId,
          mediaType: data.mediaType,
        },
      },
      create: {
        userId,
        tmdbId: data.tmdbId,
        mediaType: data.mediaType,
        title: data.title,
        posterPath: data.posterPath,
      },
      update: { title: data.title, posterPath: data.posterPath },
    });
    res.json(item);
  } catch (e) {
    next(e);
  }
});

router.get('/', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const { limit, cursor } = watchlistQuerySchema.parse(req.query);
    const items = await prisma.watchlistItem.findMany({
      where: { userId },
      orderBy: { addedAt: 'desc' },
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    });
    const hasMore = items.length > limit;
    const page = hasMore ? items.slice(0, limit) : items;
    res.json({
      items: page,
      nextCursor: hasMore ? page[page.length - 1]?.id : null,
    });
  } catch (e) {
    next(e);
  }
});

router.get('/contains/:tmdbId', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const tmdbId = Number(req.params.tmdbId);
    if (!Number.isFinite(tmdbId)) throw new HttpError(400, 'BAD_ID', 'Invalid tmdbId');
    const { mediaType } = containsQuerySchema.parse(req.query);
    const item = await prisma.watchlistItem.findUnique({
      where: { userId_tmdbId_mediaType: { userId, tmdbId, mediaType } },
    });
    res.json({ inWatchlist: !!item });
  } catch (e) {
    next(e);
  }
});

router.delete('/:tmdbId', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const tmdbId = Number(req.params.tmdbId);
    if (!Number.isFinite(tmdbId)) throw new HttpError(400, 'BAD_ID', 'Invalid tmdbId');
    const { mediaType } = containsQuerySchema.parse(req.query);
    const result = await prisma.watchlistItem.deleteMany({
      where: { userId, tmdbId, mediaType },
    });
    if (result.count === 0) throw new HttpError(404, 'NOT_FOUND', 'Not in watchlist');
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
