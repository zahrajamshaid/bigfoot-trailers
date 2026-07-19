import { Reflector } from '@nestjs/core';
import { ROLES_KEY, UserRole } from '../../common/decorators';
import { SalesOrdersController } from './sales-orders.controller';

/**
 * Who can do what to an estimate / sales order.
 *
 * The bug this pins: the Quick Estimate flow (a fast lane built FOR sales)
 * creates a draft and immediately approves it. Approve was OWNER/OFFICE only,
 * so a sales rep got "resource forbidden" the moment they tried to raise a
 * quote — the feature's primary user couldn't use it.
 *
 * The rule now:
 *   - SALES can drive an estimate through its quote lifecycle: create, price,
 *     approve (allocate SO# + push a QBO Estimate), send, retry a failed sync,
 *     and read/print it. An Estimate is a quote, not a commitment.
 *   - ACCEPT — turning the quote into a real production trailer — is the
 *     committed step and stays OWNER/OFFICE.
 */
describe('Sales Orders RBAC', () => {
  const reflector = new Reflector();

  const rolesFor = (method: string): UserRole[] | undefined => {
    const proto = SalesOrdersController.prototype as unknown as Record<string, unknown>;
    return reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      proto[method] as () => unknown,
      SalesOrdersController,
    ]);
  };

  it.each([
    'approve',
    'retrySync',
    'send',
    'create',
    'preview',
    'getCatalog',
    'importFromQbo',
    'syncEstimates',
  ])('lets SALES drive the estimate quote lifecycle: %s', (method) => {
    expect(rolesFor(method)).toContain(UserRole.SALES);
  });

  it('does NOT let SALES accept — converting to a production trailer is committed', () => {
    const roles = rolesFor('accept');
    expect(roles).toBeDefined();
    expect(roles).not.toContain(UserRole.SALES);
    expect([...roles!].sort()).toEqual([UserRole.OFFICE, UserRole.OWNER].sort());
  });

  it('keeps PRICED documents off the shop floor', () => {
    // The priced sales-order PDF shows dollars — owner/office/sales only.
    // (The no-price WORK ORDER, packingSlipPdf, is deliberately floor-wide.)
    const roles = rolesFor('salesOrderPdf');
    expect(roles).toBeDefined();
    for (const floor of [
      UserRole.WORKER,
      UserRole.DRIVER,
      UserRole.QC_INSPECTOR,
      UserRole.PARTS,
      UserRole.PURCHASING,
    ]) {
      expect(roles).not.toContain(floor);
    }
  });

  it('declares roles on every route handler — no accidental "everyone allowed"', () => {
    // The route handlers on this controller. If a new endpoint is added, add it
    // here — a route with no @Roles is "everyone allowed" under RolesGuard, and
    // this list is the reminder to make that choice deliberately. (Non-route
    // helpers like assertEnabled are intentionally excluded.)
    const routes = [
      'getCatalog',
      'preview',
      'create',
      'list',
      'findOne',
      'estimatePdf',
      'packingSlipPdf',
      'salesOrderPdf',
      'approve',
      'retrySync',
      'send',
      'accept',
      'importFromQbo',
      'syncEstimates',
      'reconcileAcceptance',
    ];
    for (const name of routes) {
      expect({ name, roles: rolesFor(name) }).toEqual({
        name,
        roles: expect.any(Array),
      });
    }
  });
});
