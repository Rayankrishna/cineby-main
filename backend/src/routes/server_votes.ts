import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { requireAuth } from '../middleware/auth';
import { HttpError } from '../middleware/error';

const router = Router();
router.use(requireAuth);

const voteSchema = z.object({
  tmdbId: z.number().int().positive(),
  mediaType: z.enum(['movie', 'tv']),
  serverName: z.string().min(1).max(64),
});

/// Record a successful playback for (tmdbId, mediaType, serverName). Bumps
/// successCount + lastSuccess. Idempotent in the sense that re-posting the
/// same tuple keeps increasing the count — every successful playback is a
/// fresh vote.
router.post('/', async (req, res, next) => {
  try {
    const data = voteSchema.parse(req.body);
    const vote = await prisma.serverVote.upsert({
      where: {
        tmdbId_mediaType_serverName: {
          tmdbId: data.tmdbId,
          mediaType: data.mediaType,
          serverName: data.serverName,
        },
      },
      create: {
        tmdbId: data.tmdbId,
        mediaType: data.mediaType,
        serverName: data.serverName,
        successCount: 1,
        lastSuccess: new Date(),
      },
      update: {
        successCount: { increment: 1 },
        lastSuccess: new Date(),
      },
    });
    res.json(vote);
  } catch (e) {
    next(e);
  }
});

/// Return all known server rankings for a title, ordered by success count
/// (descending) and recency (most-recently-successful tiebreaker). Clients
/// pick the first entry as the default Source on detail pages. Empty
/// `items` means no votes yet → client falls back to `streamServers.first`.
router.get('/:tmdbId', async (req, res, next) => {
  try {
    const tmdbId = Number(req.params.tmdbId);
    if (!Number.isFinite(tmdbId)) {
      throw new HttpError(400, 'BAD_ID', 'Invalid tmdbId');
    }
    const mediaType = String(req.query.mediaType ?? '');
    if (mediaType !== 'movie' && mediaType !== 'tv') {
      throw new HttpError(400, 'BAD_MEDIA_TYPE', 'mediaType must be movie or tv');
    }
    const items = await prisma.serverVote.findMany({
      where: { tmdbId, mediaType },
      orderBy: [
        { successCount: 'desc' },
        { lastSuccess: 'desc' },
      ],
    });
    res.json({ items });
  } catch (e) {
    next(e);
  }
});

export default router;
