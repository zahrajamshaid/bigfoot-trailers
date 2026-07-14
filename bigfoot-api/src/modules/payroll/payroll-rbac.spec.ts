import { Reflector } from '@nestjs/core';
import { ROLES_KEY, UserRole } from '../../common/decorators';
import { PayrollController } from './payroll.controller';

/**
 * Payroll is owner / office / production_manager ONLY.
 *
 * RolesGuard grants access when a handler has no @Roles() decorator. Three
 * payroll routes had none — point-values, dollar-rates (the actual pay rates)
 * and the per-worker summary — so any logged-in worker, driver or QC inspector
 * could read them. The roles are now declared on the CONTROLLER, which makes
 * the lock the default for every route on it, including ones added later.
 *
 * This test fails if someone removes that controller-level guard.
 */
describe('Payroll RBAC', () => {
  const reflector = new Reflector();
  const ALLOWED = [
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
  ];

  it('locks the whole controller to owner / office / production_manager', () => {
    const roles = reflector.get<UserRole[]>(ROLES_KEY, PayrollController);
    expect(roles).toBeDefined();
    expect([...roles].sort()).toEqual([...ALLOWED].sort());
  });

  it('never exposes payroll to the shop floor', () => {
    const roles = reflector.get<UserRole[]>(ROLES_KEY, PayrollController) ?? [];
    for (const role of [
      UserRole.WORKER,
      UserRole.DRIVER,
      UserRole.QC_INSPECTOR,
      UserRole.SALES,
      UserRole.PARTS,
      UserRole.PURCHASING,
      UserRole.TRANSPORT_MANAGER,
    ]) {
      expect(roles).not.toContain(role);
    }
  });

  it('every route inherits the lock — no handler may be left unguarded', () => {
    const proto = PayrollController.prototype as unknown as Record<string, unknown>;
    const handlers = Object.getOwnPropertyNames(proto).filter(
      (k) => k !== 'constructor' && typeof proto[k] === 'function',
    );
    expect(handlers.length).toBeGreaterThan(0);

    for (const name of handlers) {
      // getAllAndOverride is what the guard uses: handler wins, else class.
      const roles = reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
        proto[name] as () => unknown,
        PayrollController,
      ]);
      expect(roles).toBeDefined();
      // Whatever a route declares, it can never let the floor in.
      expect(roles).not.toContain(UserRole.WORKER);
      expect(roles).not.toContain(UserRole.DRIVER);
      expect(roles).not.toContain(UserRole.QC_INSPECTOR);
    }
  });
});
