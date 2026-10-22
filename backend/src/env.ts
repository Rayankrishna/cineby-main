import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(8),
  JWT_REFRESH_SECRET: z.string().min(8),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL: z.string().default('30d'),
  PORT: z.coerce.number().default(4000),
  CORS_ORIGIN: z.string().default('*'),
  NODE_ENV: z.string().default('development'),
  // Subtitles for the web player. The API key alone allows a few anonymous
  // downloads a day; add an account's username/password for a higher quota.
  OPENSUBTITLES_API_KEY: z.string().default('0bYZnXX8ImbFRzWaobcOus2KhNzsm5hT'),
  OPENSUBTITLES_USER_AGENT: z.string().default('Reelix v1.0'),
  OPENSUBTITLES_USERNAME: z.string().optional(),
  OPENSUBTITLES_PASSWORD: z.string().optional(),
});

export const env = schema.parse(process.env);
