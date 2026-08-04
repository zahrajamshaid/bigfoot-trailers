import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { RolesGuard } from './roles.guard';
import { UserRole } from '../decorators/roles.decorator';

function createMockContext(userRole?: string): ExecutionContext {
  return {
    getHandler: jest.fn(),
    getClass: jest.fn(),
    switchToHttp: () => ({
      getRequest: () => ({
        user: userRole
          ? {
              sub: 1,
              email: 'test@test.com',
              role: userRole,
              departmentId: null,
              extraDepartmentIds: [],
              iat: 0,
              exp: 0,
            }
          : undefined,
      }),
      getResponse: jest.fn(),
      getNext: jest.fn(),
    }),
    getArgs: jest.fn(),
    getArgByIndex: jest.fn(),
    switchToRpc: jest.fn(),
    switchToWs: jest.fn(),
    getType: jest.fn(),
  } as unknown as ExecutionContext;
}

describe('RolesGuard', () => {
  let guard: RolesGuard;
  let reflector: Reflector;

  beforeEach(() => {
    reflector = new Reflector();
    guard = new RolesGuard(reflector);
  });

  it('should allow access when no @Roles() decorator is present', () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue(undefined);
    const context = createMockContext('worker');

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should allow access when user has required role', () => {
    jest
      .spyOn(reflector, 'getAllAndOverride')
      .mockReturnValue([UserRole.OWNER, UserRole.PRODUCTION_MANAGER]);
    const context = createMockContext('owner');

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should deny access when user does not have required role', () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue([UserRole.OWNER]);
    const context = createMockContext('worker');

    expect(guard.canActivate(context)).toBe(false);
  });

  it('should deny access when no user on request', () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue([UserRole.OWNER]);
    const context = createMockContext(undefined);

    expect(guard.canActivate(context)).toBe(false);
  });

  it('should work correctly for all 10 roles', () => {
    const allRoles = Object.values(UserRole);
    expect(allRoles).toHaveLength(10);

    for (const role of allRoles) {
      jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue([role]);
      const context = createMockContext(role);
      expect(guard.canActivate(context)).toBe(true);
    }
  });

  it('should deny qc_inspector when only owner and production_manager allowed', () => {
    jest
      .spyOn(reflector, 'getAllAndOverride')
      .mockReturnValue([UserRole.OWNER, UserRole.PRODUCTION_MANAGER]);
    const context = createMockContext('qc_inspector');

    expect(guard.canActivate(context)).toBe(false);
  });

  it('should allow production_manager to cover QC when allowed', () => {
    jest
      .spyOn(reflector, 'getAllAndOverride')
      .mockReturnValue([UserRole.QC_INSPECTOR, UserRole.PRODUCTION_MANAGER]);
    const context = createMockContext('production_manager');

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should allow office wherever owner is allowed (owner parity)', () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue([UserRole.OWNER]);
    const context = createMockContext('office');

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should allow office on an owner-only route it is not explicitly listed on', () => {
    jest
      .spyOn(reflector, 'getAllAndOverride')
      .mockReturnValue([UserRole.OWNER, UserRole.PRODUCTION_MANAGER]);
    const context = createMockContext('office');

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should allow office on ANY gate — full access, even routes owner is not listed on', () => {
    // Delivery complete/fail are gated to driver/transport with no owner; office
    // must still pass (it is a full-access back-office admin).
    jest
      .spyOn(reflector, 'getAllAndOverride')
      .mockReturnValue([UserRole.DRIVER, UserRole.TRANSPORT_MANAGER]);
    const context = createMockContext('office');

    expect(guard.canActivate(context)).toBe(true);
  });
});
