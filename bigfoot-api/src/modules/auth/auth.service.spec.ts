import { Test, TestingModule } from '@nestjs/testing';
import { UnauthorizedException, ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const mockUser = {
  id: BigInt(1),
  email: 'admin@bigfoottrailers.com',
  fullName: 'Admin User',
  passwordHash: '', // set in beforeEach
  role: 'owner',
  primaryDepartmentId: null,
  isActive: true,
};

const mockRefreshToken = {
  id: BigInt(100),
  userId: BigInt(1),
  tokenHash: 'stored_hash',
  deviceLabel: null,
  expiresAt: new Date(Date.now() + 7 * 86_400_000), // 7 days ahead
  revokedAt: null,
  createdAt: new Date(),
  user: {
    id: BigInt(1),
    email: 'admin@bigfoottrailers.com',
    role: 'owner',
    primaryDepartmentId: null,
    isActive: true,
  },
};

const mockPrisma = {
  user: {
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  refreshToken: {
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    updateMany: jest.fn(),
  },
};

const mockJwtService = {
  sign: jest.fn().mockReturnValue('signed.jwt.token'),
  decode: jest.fn().mockReturnValue({ exp: Math.floor(Date.now() / 1000) + 900 }),
};

const mockConfigService = {
  get: jest.fn((key: string, defaultValue?: string) => {
    const map: Record<string, string> = {
      JWT_SECRET: 'test-secret-key-at-least-32-chars-long',
      JWT_ACCESS_EXPIRY: '15m',
      JWT_REFRESH_EXPIRY: '7d',
    };
    return map[key] ?? defaultValue;
  }),
};

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(async () => {
    // Hash a known password for tests
    mockUser.passwordHash = await bcrypt.hash('ValidPass123', 10);

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: JwtService, useValue: mockJwtService },
        { provide: ConfigService, useValue: mockConfigService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);

    // Reset all mocks
    jest.clearAllMocks();

    // Re-apply default mock return for decode
    mockJwtService.sign.mockReturnValue('signed.jwt.token');
    mockJwtService.decode.mockReturnValue({ exp: Math.floor(Date.now() / 1000) + 900 });
  });

  // =========================================================================
  // LOGIN
  // =========================================================================

  describe('login', () => {
    it('should return a token pair for valid credentials', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({ ...mockUser });
      mockPrisma.refreshToken.create.mockResolvedValue({ id: BigInt(101) });

      const result = await service.login('admin@bigfoottrailers.com', 'ValidPass123');

      expect(result).toHaveProperty('accessToken', 'signed.jwt.token');
      expect(result).toHaveProperty('refreshToken');
      expect(typeof result.refreshToken).toBe('string');
      expect(result.refreshToken.length).toBeGreaterThan(0);
      expect(result).toHaveProperty('expiresIn');
      expect(typeof result.expiresIn).toBe('number');

      // Verify JWT was signed with correct payload shape
      expect(mockJwtService.sign).toHaveBeenCalledWith(
        expect.objectContaining({
          sub: 1,
          email: 'admin@bigfoottrailers.com',
          role: 'owner',
          departmentId: null,
        }),
      );

      // Verify refresh token was stored in DB
      expect(mockPrisma.refreshToken.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          userId: BigInt(1),
          tokenHash: expect.any(String),
          expiresAt: expect.any(Date),
        }),
      });
    });

    it('should throw UnauthorizedException for non-existent email', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.login('nobody@example.com', 'AnyPassword1'),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw UnauthorizedException for wrong password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({ ...mockUser });

      await expect(
        service.login('admin@bigfoottrailers.com', 'WrongPassword1'),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw ForbiddenException for deactivated account', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        isActive: false,
      });

      await expect(
        service.login('admin@bigfoottrailers.com', 'ValidPass123'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should not reveal whether email exists in error message', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      try {
        await service.login('nobody@example.com', 'AnyPassword1');
        fail('Should have thrown');
      } catch (error) {
        const response = (error as UnauthorizedException).getResponse() as Record<string, string>;
        expect(response.message).toBe('Invalid email or password');
      }
    });
  });

  // =========================================================================
  // REFRESH
  // =========================================================================

  describe('refresh', () => {
    it('should rotate token and return new pair', async () => {
      // We need to match the hash, so spy on hashToken
      const rawToken = 'valid-refresh-token';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
      });
      mockPrisma.refreshToken.update.mockResolvedValue({});
      mockPrisma.refreshToken.create.mockResolvedValue({ id: BigInt(102) });

      const result = await service.refresh(rawToken);

      expect(result).toHaveProperty('accessToken');
      expect(result).toHaveProperty('refreshToken');

      // Old token should be revoked
      expect(mockPrisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: mockRefreshToken.id },
        data: { revokedAt: expect.any(Date) },
      });

      // New refresh token should be created
      expect(mockPrisma.refreshToken.create).toHaveBeenCalled();
    });

    it('should throw UnauthorizedException for invalid token', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(null);

      await expect(service.refresh('invalid-token')).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('should revoke all tokens on reuse of revoked token', async () => {
      const rawToken = 'reused-revoked-token';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
        revokedAt: new Date(), // Already revoked — reuse detected
      });
      mockPrisma.refreshToken.updateMany.mockResolvedValue({ count: 3 });

      await expect(service.refresh(rawToken)).rejects.toThrow(
        UnauthorizedException,
      );

      // All tokens for user should be revoked
      expect(mockPrisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { userId: mockRefreshToken.userId, revokedAt: null },
        data: { revokedAt: expect.any(Date) },
      });
    });

    it('should throw UnauthorizedException for expired token', async () => {
      const rawToken = 'expired-refresh-token';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
        expiresAt: new Date(Date.now() - 1000), // Expired
      });

      await expect(service.refresh(rawToken)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('should throw ForbiddenException if user deactivated since token issued', async () => {
      const rawToken = 'deactivated-user-token';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
        user: { ...mockRefreshToken.user, isActive: false },
      });

      await expect(service.refresh(rawToken)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  // =========================================================================
  // LOGOUT
  // =========================================================================

  describe('logout', () => {
    it('should revoke the refresh token', async () => {
      const rawToken = 'token-to-revoke';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
      });
      mockPrisma.refreshToken.update.mockResolvedValue({});

      await service.logout(rawToken);

      expect(mockPrisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: mockRefreshToken.id },
        data: { revokedAt: expect.any(Date) },
      });
    });

    it('should be idempotent — no error if token already revoked', async () => {
      const rawToken = 'already-revoked';
      const hashedToken = service.hashToken(rawToken);

      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...mockRefreshToken,
        tokenHash: hashedToken,
        revokedAt: new Date(),
      });

      // Should not throw
      await expect(service.logout(rawToken)).resolves.toBeUndefined();
      expect(mockPrisma.refreshToken.update).not.toHaveBeenCalled();
    });

    it('should be idempotent — no error if token does not exist', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(null);

      await expect(service.logout('nonexistent-token')).resolves.toBeUndefined();
    });
  });

  // =========================================================================
  // PUSH TOKEN
  // =========================================================================

  describe('updatePushToken', () => {
    it('should update the user push token', async () => {
      mockPrisma.user.update.mockResolvedValue({});

      await service.updatePushToken(BigInt(1), 'fcm-token-xyz');

      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: BigInt(1) },
        data: { pushToken: 'fcm-token-xyz' },
      });
    });
  });
});
