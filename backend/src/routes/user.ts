import { Router } from 'express';
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
      createdAt: user.createdAt,
    });
  } catch (e) {
    next(e);
  }
});

export default router;
