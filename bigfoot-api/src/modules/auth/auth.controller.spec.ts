import { Test, TestingModule } from '@nestjs/testing';
import { AuthController } from './auth.controller';
import { AuthService, TokenPair } from './auth.service';

const mockTokenPair: TokenPair = {
  accessToken: 'signed.jwt.token',
  refreshToken: 'random-refresh-token',
  expiresIn: 900,
};

const mockAuthService = {
  login: jest.fn().mockResolvedValue(mockTokenPair),
  refresh: jest.fn().mockResolvedValue(mockTokenPair),
  logout: jest.fn().mockResolvedValue(undefined),
  updatePushToken: jest.fn().mockResolvedValue(undefined),
};

describe('AuthController', () => {
  let controller: AuthController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AuthController],
      providers: [{ provide: AuthService, useValue: mockAuthService }],
    }).compile();

    controller = module.get<AuthController>(AuthController);
    jest.clearAllMocks();
  });

  describe('POST /auth/login', () => {
    it('should call authService.login and return token pair', async () => {
      const dto = { email: 'admin@bigfoottrailers.com', password: 'ValidPass123' };
      const result = await controller.login(dto);

      expect(mockAuthService.login).toHaveBeenCalledWith(dto.email, dto.password);
      expect(result).toEqual(mockTokenPair);
    });
  });

  describe('POST /auth/refresh', () => {
    it('should call authService.refresh and return new token pair', async () => {
      const dto = { refreshToken: 'old-refresh-token' };
      const result = await controller.refresh(dto);

      expect(mockAuthService.refresh).toHaveBeenCalledWith(dto.refreshToken);
      expect(result).toEqual(mockTokenPair);
    });
  });

  describe('POST /auth/logout', () => {
    it('should call authService.logout and return success message', async () => {
      const dto = { refreshToken: 'token-to-revoke' };
      const result = await controller.logout(dto);

      expect(mockAuthService.logout).toHaveBeenCalledWith(dto.refreshToken);
      expect(result).toEqual({ message: 'Logged out successfully' });
    });
  });

  describe('PATCH /auth/push-token', () => {
    it('should call authService.updatePushToken and return success message', async () => {
      const user = { sub: 1, email: 'admin@bigfoottrailers.com', role: 'owner', departmentId: null, iat: 0, exp: 0 };
      const dto = { pushToken: 'fcm-token-xyz' };
      const result = await controller.updatePushToken(user, dto);

      expect(mockAuthService.updatePushToken).toHaveBeenCalledWith(BigInt(1), 'fcm-token-xyz');
      expect(result).toEqual({ message: 'Push token updated' });
    });
  });
});
