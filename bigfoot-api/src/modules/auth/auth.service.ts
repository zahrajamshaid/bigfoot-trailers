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

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {
    // Parse JWT_REFRESH_EXPIRY (e.g. "7d") into milliseconds
    this.refreshExpiryMs = this.parseDurationToMs(
      this.configService.get<string>('JWT_REFRESH_EXPIRY', '7d'),
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

    // 3. Check if already revoked — possible token reuse attack
    if (storedToken.revokedAt) {
      this.logger.warn(
        `Refresh token reuse detected for user ${storedToken.userId}. Revoking all tokens.`,
      );
      await this.revokeAllUserTokens(storedToken.userId);
      throw new AppError(
        ErrorCode.UNAUTHORIZED,
        'Refresh token has been revoked — all sessions terminated',
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

  /** Revoke all refresh tokens for a user (token reuse protection). */
  private async revokeAllUserTokens(userId: bigint): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
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
