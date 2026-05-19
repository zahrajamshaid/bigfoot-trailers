import { Controller, Post, Patch, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { LoginDto, RefreshDto, LogoutDto, PushTokenDto } from './dto';
import { Public } from '../../common/decorators/public.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ---------------------------------------------------------------------------
  // POST /auth/login
  // ---------------------------------------------------------------------------
  @Post('login')
  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 5 } }) // 5 attempts per minute per IP
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Exchange email + password for access + refresh tokens' })
  @ApiResponse({ status: 200, description: 'Login successful — tokens returned' })
  @ApiResponse({ status: 401, description: 'Invalid email or password' })
  @ApiResponse({ status: 403, description: 'Account deactivated' })
  @ApiResponse({ status: 429, description: 'Too many login attempts' })
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto.email, dto.password);
  }

  // ---------------------------------------------------------------------------
  // POST /auth/refresh
  // ---------------------------------------------------------------------------
  @Post('refresh')
  @Public()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Exchange refresh token for a new access token (rotation)' })
  @ApiResponse({ status: 200, description: 'Token pair rotated successfully' })
  @ApiResponse({ status: 401, description: 'Invalid or expired refresh token' })
  async refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  // ---------------------------------------------------------------------------
  // POST /auth/logout
  // ---------------------------------------------------------------------------
  @Post('logout')
  @Public()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Revoke the current refresh token' })
  @ApiResponse({ status: 200, description: 'Refresh token revoked (idempotent)' })
  async logout(@Body() dto: LogoutDto) {
    await this.authService.logout(dto.refreshToken);
    return { message: 'Logged out successfully' };
  }

  // ---------------------------------------------------------------------------
  // PATCH /auth/push-token
  // ---------------------------------------------------------------------------
  @Patch('push-token')
  @ApiBearerAuth('JWT')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Register or update FCM device push token' })
  @ApiResponse({ status: 200, description: 'Push token updated' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async updatePushToken(@CurrentUser() user: JwtPayload, @Body() dto: PushTokenDto) {
    await this.authService.updatePushToken(BigInt(user.sub), dto.pushToken);
    return { message: 'Push token updated' };
  }
}
