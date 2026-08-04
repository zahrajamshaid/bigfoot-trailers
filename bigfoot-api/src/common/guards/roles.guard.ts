import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY, UserRole } from '../decorators/roles.decorator';
import { JwtPayload } from '../decorators/current-user.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    // If no @Roles() decorator is present, allow access (auth-only check)
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<{ user?: JwtPayload }>();
    const user = request.user;

    if (!user) {
      return false;
    }

    const role = user.role as UserRole;

    // OFFICE is a full-access back-office admin: it passes every role gate,
    // present and future. Owner parity alone wasn't enough — some endpoints
    // (e.g. completing/failing a delivery) are gated to driver/transport and
    // never list the owner, so office was still blocked there. Both office
    // accounts are trusted, so office bypasses the role check entirely.
    if (role === UserRole.OFFICE) {
      return true;
    }

    return requiredRoles.includes(role);
  }
}
