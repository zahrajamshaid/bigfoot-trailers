import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../../prisma/prisma.service';
import { JwtPayload } from '../../common/decorators/current-user.decorator';
import { AppError, ErrorCode } from '../../common/errors';

/** Full decoded JWT payload including iat/exp set by jsonwebtoken. */
interface JwtTokenPayload {
  sub: number;
  email: string;
  role: string;
  departmentId: number | null;
  extraDepartmentIds?: number[];
  iat: number;
  exp: number;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    const secret = configService.get<string>('JWT_SECRET');
    if (!secret) {
      throw new Error('JWT_SECRET environment variable is not set');
    }

    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: secret,
    });
  }

  /**
   * Called by Passport after JWT signature verification.
   * Returns the payload that will be attached to request.user.
   */
  async validate(payload: JwtTokenPayload): Promise<JwtPayload> {
    // Verify the user still exists and is active
    const user = await this.prisma.user.findUnique({
      where: { id: BigInt(payload.sub) },
      select: { id: true, isActive: true },
    });

    if (!user || !user.isActive) {
      throw new AppError(
        ErrorCode.UNAUTHORIZED,
        'User account is deactivated or not found',
      );
    }

    return {
      sub: payload.sub,
      email: payload.email,
      role: payload.role,
      departmentId: payload.departmentId,
      extraDepartmentIds: payload.extraDepartmentIds ?? [],
      iat: payload.iat,
      exp: payload.exp,
    };
  }
}
