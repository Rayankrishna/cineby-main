import { Router } from 'express';
import { prisma } from '../db';
import { hashPassword, verifyPassword } from '../lib/password';
import {
  refreshTokenExpiry,
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../lib/jwt';
import { loginSchema, refreshSchema, registerSchema } from '../schemas/auth';
import { HttpError } from '../middleware/error';
import { authLimiter } from '../middleware/rateLimit';

const router = Router();
router.use(authLimiter);

const issueTokens = async (userId: string, email: string) => {
  const accessToken = signAccessToken({ sub: userId, email });
  const refreshToken = signRefreshToken({ sub: userId, email });
  await prisma.refreshToken.create({
    data: { token: refreshToken, userId, expiresAt: refreshTokenExpiry() },
  });
  return { accessToken, refreshToken };
};

const publicUser = (u: {
  id: string;
  name: string;
  email: string;
  avatarUrl: string | null;
  createdAt: Date;
}) => ({
  id: u.id,
  name: u.name,
  email: u.email,
  avatarUrl: u.avatarUrl,
  createdAt: u.createdAt,
});

router.post('/register', async (req, res, next) => {
  try {
    const { name, email, password } = registerSchema.parse(req.body);
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) throw new HttpError(409, 'EMAIL_TAKEN', 'Email already registered');
    const passwordHash = await hashPassword(password);
    const user = await prisma.user.create({ data: { name, email, passwordHash } });
    const tokens = await issueTokens(user.id, user.email);
    res.status(201).json({ user: publicUser(user), ...tokens });
  } catch (e) {
    next(e);
  }
});

router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = loginSchema.parse(req.body);
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) throw new HttpError(401, 'BAD_CREDENTIALS', 'Invalid email or password');
    const ok = await verifyPassword(password, user.passwordHash);
    if (!ok) throw new HttpError(401, 'BAD_CREDENTIALS', 'Invalid email or password');
    const tokens = await issueTokens(user.id, user.email);
    res.json({ user: publicUser(user), ...tokens });
  } catch (e) {
    next(e);
  }
});

router.post('/refresh', async (req, res, next) => {
  try {
    const { refreshToken } = refreshSchema.parse(req.body);
    const payload = verifyRefreshToken(refreshToken);
    const record = await prisma.refreshToken.findUnique({ where: { token: refreshToken } });
    if (!record || record.revoked || record.expiresAt < new Date()) {
      throw new HttpError(401, 'INVALID_REFRESH', 'Refresh token is not valid');
    }
    const accessToken = signAccessToken({ sub: payload.sub, email: payload.email });
    res.json({ accessToken });
  } catch (e) {
    if (e instanceof HttpError) return next(e);
    return next(new HttpError(401, 'INVALID_REFRESH', 'Refresh token is not valid'));
  }
});

router.post('/logout', async (req, res, next) => {
  try {
    const { refreshToken } = refreshSchema.parse(req.body);
    await prisma.refreshToken.updateMany({
      where: { token: refreshToken },
      data: { revoked: true },
    });
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
