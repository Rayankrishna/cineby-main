import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db';
import { requireAuth } from '../middleware/auth';
import { HttpError } from '../middleware/error';

const router = Router();
router.use(requireAuth);

router.get('/me', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new HttpError(404, 'NOT_FOUND', 'User not found');
    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      avatarUrl: user.avatarUrl,
      createdAt: user.createdAt,
    });
  } catch (e) {
    next(e);
  }
});

// Update profile fields. Currently only avatarUrl. Send `null` (or empty
// string, which we coerce to null) to clear it.
const updateMeSchema = z.object({
  avatarUrl: z
    .string()
    .url()
    .max(2048)
    .nullable()
    .optional()
    .or(z.literal('').transform(() => null)),
});

router.patch('/me', async (req, res, next) => {
  try {
    const userId = req.userId!;
    const data = updateMeSchema.parse(req.body);
    const user = await prisma.user.update({
      where: { id: userId },
      data: {
        ...(data.avatarUrl !== undefined ? { avatarUrl: data.avatarUrl } : {}),
      },
    });
    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      avatarUrl: user.avatarUrl,
      createdAt: user.createdAt,
    });
  } catch (e) {
    next(e);
  }
});

export default router;
