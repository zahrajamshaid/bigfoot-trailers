import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';

/**
 * JWT payload shape attached to request.user by Passport.
 * Will be fully typed once the auth module is implemented.
 */
export interface JwtPayload {
  sub: number;
  email: string;
  role: string;
  departmentId: number | null;
  iat: number;
  exp: number;
}

/**
 * Extract the authenticated user from the JWT on the request.
 * Usage: @CurrentUser() user: JwtPayload
 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): JwtPayload => {
    const request = ctx.switchToHttp().getRequest<Request>();
    return request.user as JwtPayload;
  },
);
