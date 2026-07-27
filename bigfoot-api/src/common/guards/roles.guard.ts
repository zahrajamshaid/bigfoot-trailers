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

    // OFFICE is a back-office admin peer of the owner: anywhere the owner is
    // allowed, office is allowed too. This keeps office at full owner parity
    // across every endpoint (present and future) without listing it on each
    // @Roles() decorator. Owner-only routes therefore also admit office.
    if (role === UserRole.OFFICE && requiredRoles.includes(UserRole.OWNER)) {
      return true;
    }

    return requiredRoles.includes(role);
  }
}
