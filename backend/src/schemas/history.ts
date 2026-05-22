import { z } from 'zod';

export const mediaTypeSchema = z.enum(['movie', 'tv']);

export const upsertHistorySchema = z
  .object({
    tmdbId: z.number().int().positive(),
    mediaType: mediaTypeSchema,
    seasonNumber: z.number().int().nonnegative().optional(),
    episodeNumber: z.number().int().nonnegative().optional(),
    progressSeconds: z.number().int().nonnegative(),
    durationSeconds: z.number().int().positive().optional(),
    title: z.string().optional(),
    posterPath: z.string().optional(),
    backdropPath: z.string().optional(),
  })
  .superRefine((val, ctx) => {
    if (val.mediaType === 'tv') {
      if (val.seasonNumber == null || val.episodeNumber == null) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'seasonNumber and episodeNumber are required for tv',
        });
      }
    }
  });

export const listHistoryQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().optional(),
  mediaType: mediaTypeSchema.optional(),
});

export const getOneHistoryQuerySchema = z.object({
  mediaType: mediaTypeSchema,
  season: z.coerce.number().int().nonnegative().optional(),
  episode: z.coerce.number().int().nonnegative().optional(),
});
