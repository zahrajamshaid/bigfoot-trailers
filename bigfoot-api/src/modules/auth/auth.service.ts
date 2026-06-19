import { Injectable, Logger } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';

/** Shape of the JWT access token payload (before signing). */
export interface AccessTokenPayload {
  sub: number;
  email: string;
  role: string;
  departmentId: number | null;
  extraDepartmentIds: number[];
}

/** Shape returned to the client on successful login / refresh. */
export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly refreshExpiryMs: number;
  private readonly reuseGraceMs: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {
    // Parse JWT_REFRESH_EXPIRY (e.g. "7d") into milliseconds
    this.refreshExpiryMs = this.parseDurationToMs(
      this.configService.get<string>('JWT_REFRESH_EXPIRY', '7d'),
    );
    // Grace window during which a *just-rotated* refresh token can be presented
    // again without raising an alarm. Absorbs benign client races: a proactive
    // timer refresh firing alongside a 401-triggered retry, an app being
    // suspended mid-rotation on iOS, a desktop client whose tab was paused
    // while the timer fired. 5 minutes covers every real-world scenario we've
    // seen without giving a thief a meaningful window.
    this.reuseGraceMs = this.parseDurationToMs(
      this.configService.get<string>('JWT_REFRESH_REUSE_GRACE', '5m'),
    );
  }

  // ---------------------------------------------------------------------------
  // POST /auth/login
  // ---------------------------------------------------------------------------
  async login(email: string, password: string): Promise<TokenPair> {
    // 1. Find user by email
    const user = await this.prisma.user.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        fullName: true,
        passwordHash: true,
        role: true,
        primaryDepartmentId: true,
        extraDepartmentIds: true,
        isActive: true,
      },
    });

    if (!user) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid email or password');
    }

    // 2. Check account is active
    if (!user.isActive) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Account has been deactivated');
    }

    // 3. Verify password against bcrypt hash
    const passwordValid = await bcrypt.compare(password, user.passwordHash);
    if (!passwordValid) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid email or password');
    }

    // 4. Generate token pair
    return this.generateTokenPair({
      sub: Number(user.id),
      email: user.email!,
      role: user.role,
      departmentId: user.primaryDepartmentId,
      extraDepartmentIds: user.extraDepartmentIds,
    });
  }

  // ---------------------------------------------------------------------------
  // POST /auth/refresh
  // ---------------------------------------------------------------------------
  async refresh(rawRefreshToken: string): Promise<TokenPair> {
    // 1. Hash the incoming token to look it up
    const tokenHash = this.hashToken(rawRefreshToken);

    // 2. Find the refresh token record
    const storedToken = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            role: true,
            primaryDepartmentId: true,
            extraDepartmentIds: true,
            isActive: true,
          },
        },
      },
    });

    if (!storedToken) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid refresh token');
    }

    // 3. Token already revoked. Distinguish a benign client race from a real
    //    reuse attack by how long ago it was rotated.
    if (storedToken.revokedAt) {
      const msSinceRevoked = Date.now() - storedToken.revokedAt.getTime();

      if (msSinceRevoked <= this.reuseGraceMs) {
        // Within the grace window: a concurrent refresh just rotated this token
        // a moment ago. Re-issue a fresh pair instead of nuking every session.
        if (!storedToken.user.isActive) {
          throw new AppError(ErrorCode.FORBIDDEN, 'Account has been deactivated');
        }
        this.logger.log(
          `Refresh token reused ${msSinceRevoked}ms after rotation for user ` +
            `${storedToken.userId} (within ${this.reuseGraceMs}ms grace) — re-issuing.`,
        );
        return this.generateTokenPair({
          sub: Number(storedToken.user.id),
          email: storedToken.user.email!,
          role: storedToken.user.role,
          departmentId: storedToken.user.primaryDepartmentId,
          extraDepartmentIds: storedToken.user.extraDepartmentIds,
        });
      }

      // Reuse past the grace window. The OWASP recommendation is to nuke
      // every session for the user — but in practice we're an internal app
      // with employees on 3-5 devices each, and most reuse events are
      // network drops / suspended apps / queued retries rather than theft.
      // The mass revoke kept booting admin off every device whenever a
      // single stale request landed; the false-positive cost dwarfs the
      // marginal theft-detection benefit. We now reject just the offending
      // token + log loudly. Other sessions stay alive.
      this.logger.warn(
        `Refresh token reuse past grace (${Math.round(msSinceRevoked / 1000)}s ` +
          `since rotation, grace=${Math.round(this.reuseGraceMs / 1000)}s) ` +
          `for user ${storedToken.userId}. Rejecting this token; ` +
          `other sessions left intact.`,
      );
      throw new AppError(
        ErrorCode.UNAUTHORIZED,
        'Refresh token has already been used',
      );
    }

    // 4. Check expiry
    if (storedToken.expiresAt < new Date()) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Refresh token has expired');
    }

    // 5. Check user is still active
    if (!storedToken.user.isActive) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Account has been deactivated');
    }

    // 6. Rotate: revoke old token, issue new pair
    await this.prisma.refreshToken.update({
      where: { id: storedToken.id },
      data: { revokedAt: new Date() },
    });

    return this.generateTokenPair({
      sub: Number(storedToken.user.id),
      email: storedToken.user.email!,
      role: storedToken.user.role,
      departmentId: storedToken.user.primaryDepartmentId,
      extraDepartmentIds: storedToken.user.extraDepartmentIds,
    });
  }

  // ---------------------------------------------------------------------------
  // POST /auth/logout
  // ---------------------------------------------------------------------------
  async logout(rawRefreshToken: string): Promise<void> {
    const tokenHash = this.hashToken(rawRefreshToken);

    const storedToken = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
    });

    if (!storedToken || storedToken.revokedAt) {
      // Idempotent — already revoked or doesn't exist
      return;
    }

    await this.prisma.refreshToken.update({
      where: { id: storedToken.id },
      data: { revokedAt: new Date() },
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /auth/push-token
  // ---------------------------------------------------------------------------
  async updatePushToken(userId: bigint, pushToken: string): Promise<void> {
    await this.prisma.user.update({
      where: { id: userId },
      data: { pushToken },
    });
  }

  // ---------------------------------------------------------------------------
  // PRIVATE HELPERS
  // ---------------------------------------------------------------------------

  /**
   * Generate a signed JWT access token + a random refresh token,
   * storing the refresh token hash in the database.
   */
  private async generateTokenPair(payload: AccessTokenPayload): Promise<TokenPair> {
    const accessToken = this.jwtService.sign(payload);

    // Cryptographically random refresh token — never stored raw
    const rawRefreshToken = crypto.randomBytes(48).toString('base64url');
    const tokenHash = this.hashToken(rawRefreshToken);

    await this.prisma.refreshToken.create({
      data: {
        userId: BigInt(payload.sub),
        tokenHash,
        expiresAt: new Date(Date.now() + this.refreshExpiryMs),
      },
    });

    const decoded = this.jwtService.decode(accessToken) as { exp: number };

    return {
      accessToken,
      refreshToken: rawRefreshToken,
      expiresIn: decoded.exp - Math.floor(Date.now() / 1000),
    };
  }

  /** SHA-256 hash of a raw token string. */
  hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  /** Parse a duration string like "7d", "15m", "1h" to milliseconds. */
  private parseDurationToMs(duration: string): number {
    const match = duration.match(/^(\d+)([smhd])$/);
    if (!match) {
      throw new Error(
        `Invalid duration format: "${duration}". Use e.g. "7d", "15m", "1h".`,
      );
    }
    const value = parseInt(match[1], 10);
    const unit = match[2];
    const multipliers: Record<string, number> = {
      s: 1_000,
      m: 60_000,
      h: 3_600_000,
      d: 86_400_000,
    };
    return value * multipliers[unit];
  }
}
