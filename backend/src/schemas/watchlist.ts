import { z } from 'zod';
import { mediaTypeSchema } from './history';

export const addWatchlistSchema = z.object({
  tmdbId: z.number().int().positive(),
  mediaType: mediaTypeSchema,
  title: z.string().optional(),
  posterPath: z.string().optional(),
});

export const watchlistQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  cursor: z.string().optional(),
});

export const containsQuerySchema = z.object({
  mediaType: mediaTypeSchema,
});
