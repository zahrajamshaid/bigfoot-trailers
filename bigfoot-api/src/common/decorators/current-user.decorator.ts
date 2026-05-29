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
  /**
   * Additional department IDs this user can view queues for, on top of
   * `departmentId` (their primary). Empty array for normal accounts; only
   * populated for "master" accounts like paint-master (PAINT_A + PAINT_B)
   * or wire/hyd master (WIRE + HYDRAULICS).
   */
  extraDepartmentIds: number[];
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
