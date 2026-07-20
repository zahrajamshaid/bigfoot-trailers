import { Reflector } from '@nestjs/core';
import { ROLES_KEY, UserRole } from '../../common/decorators';
import { CustomersController } from './customers.controller';

/**
 * Customers are commercial data — owner, office and sales only.
 *
 * Reading and searching the customer book used to include production and
 * transport managers; they run the floor and the yard and don't need customer
 * contact details, so they're off it now. This pins the whole controller to the
 * commercial roles and fails if a floor/yard role is ever let back in.
 */
describe('Customers RBAC', () => {
  const reflector = new Reflector();
  const COMMERCIAL = [UserRole.OWNER, UserRole.OFFICE, UserRole.SALES];

  const rolesFor = (method: string): UserRole[] | undefined => {
    const proto = CustomersController.prototype as unknown as Record<string, unknown>;
    return reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      proto[method] as () => unknown,
      CustomersController,
    ]);
  };

  it.each(['findAll', 'findOne'])(
    'only owner/office/sales can view customers: %s',
    (method) => {
      expect([...(rolesFor(method) ?? [])].sort()).toEqual([...COMMERCIAL].sort());
    },
  );

  it('never exposes the customer book to production/transport/floor roles', () => {
    for (const method of ['findAll', 'findOne']) {
      const roles = rolesFor(method) ?? [];
      for (const role of [
        UserRole.PRODUCTION_MANAGER,
        UserRole.TRANSPORT_MANAGER,
        UserRole.QC_INSPECTOR,
        UserRole.WORKER,
        UserRole.DRIVER,
        UserRole.PARTS,
        UserRole.PURCHASING,
      ]) {
        expect(roles).not.toContain(role);
      }
    }
  });

  it('QuickBooks sync (import/export/two-way) is open to the commercial roles', () => {
    // Sales syncs customers too — they view and create them, and a stale list
    // is what blocks them writing an estimate.
    for (const method of ['importFromQbo', 'exportToQbo', 'sync']) {
      expect([...(rolesFor(method) ?? [])].sort()).toEqual([...COMMERCIAL].sort());
    }
  });

  it('customer DELETE stays owner/office (destructive, cascades trailers)', () => {
    const roles = rolesFor('remove');
    expect(roles).not.toContain(UserRole.SALES);
    expect([...(roles ?? [])].sort()).toEqual(
      [UserRole.OWNER, UserRole.OFFICE].sort(),
    );
  });

  it('every customer route declares roles — no accidental "everyone allowed"', () => {
    for (const method of [
      'findAll',
      'findOne',
      'create',
      'update',
      'remove',
      'importFromQbo',
      'exportToQbo',
      'sync',
    ]) {
      expect(rolesFor(method)).toBeDefined();
    }
  });
});
