import type { VercelRequest, VercelResponse } from '@vercel/node';
import app from '../src/app';

export default function handler(req: VercelRequest, res: VercelResponse) {
  return app(req as unknown as Parameters<typeof app>[0], res as unknown as Parameters<typeof app>[1]);
}
