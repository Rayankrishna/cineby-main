import jwt, { SignOptions } from 'jsonwebtoken';
import { env } from '../env';

export interface AccessTokenPayload {
  sub: string;
  email: string;
}

// Access token intentionally has NO expiry — omitting `expiresIn` means the
// JWT carries no `exp` claim, so verifyAccessToken never rejects it for age.
// Users stay signed in indefinitely (no silent 15-minute logouts). Trade-off:
// these tokens can't be aged out, only invalidated by rotating
// JWT_ACCESS_SECRET. Acceptable for this app's "stay logged in" requirement.
export const signAccessToken = (payload: AccessTokenPayload) =>
  jwt.sign(payload, env.JWT_ACCESS_SECRET);

export const signRefreshToken = (payload: AccessTokenPayload) =>
  jwt.sign(payload, env.JWT_REFRESH_SECRET, {
    expiresIn: env.REFRESH_TOKEN_TTL as SignOptions['expiresIn'],
  });

export const verifyAccessToken = (token: string) =>
  jwt.verify(token, env.JWT_ACCESS_SECRET) as AccessTokenPayload & {
    iat: number;
    exp: number;
  };

export const verifyRefreshToken = (token: string) =>
  jwt.verify(token, env.JWT_REFRESH_SECRET) as AccessTokenPayload & {
    iat: number;
    exp: number;
  };

export const refreshTokenExpiry = (): Date => {
  const ttl = env.REFRESH_TOKEN_TTL;
  const match = /^(\d+)([smhd])$/.exec(ttl);
  const now = Date.now();
  if (!match) return new Date(now + 30 * 24 * 60 * 60 * 1000);
  const value = Number(match[1]);
  const unit = match[2];
  const mult =
    unit === 's' ? 1000 : unit === 'm' ? 60_000 : unit === 'h' ? 3_600_000 : 86_400_000;
  return new Date(now + value * mult);
};
