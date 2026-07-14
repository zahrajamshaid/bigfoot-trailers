import {
  diffFields,
  fieldLabel,
  formatValue,
  humanAction,
  summarize,
  Lookups,
} from './audit-humanizer';

describe('audit-humanizer', () => {
  const lookups: Lookups = {
    locations: new Map([
      [1, 'Mulberry'],
      [2, 'Atlanta'],
    ]),
    departments: new Map([[7, 'WELD']]),
    models: new Map([[192, '15TLT20']]),
    customers: new Map([['78', "Amy's Bird Sanctuary"]]),
    users: new Map([['5', 'Drew Coulter']]),
  };

  describe('humanAction', () => {
    it('turns HTTP verbs into words', () => {
      expect(humanAction('UPDATE')).toBe('Updated');
      expect(humanAction('CREATE')).toBe('Created');
    });

    it('knows the custom domain verbs', () => {
      expect(humanAction('qc.failed')).toBe('QC failed');
      expect(humanAction('trailer.jumped_to_step')).toBe('Jumped to step');
    });

    it('title-cases anything unknown rather than leaking raw', () => {
      expect(humanAction('delivery.dispatched')).toBe('Delivery Dispatched');
    });
  });

  describe('fieldLabel', () => {
    it('uses explicit labels', () => {
      expect(fieldLabel('saleStatus')).toBe('Sale status');
      expect(fieldLabel('currentLocationId')).toBe('Location');
      expect(fieldLabel('soNumber')).toBe('SO number');
    });

    it('humanises unknown camelCase', () => {
      expect(fieldLabel('someNewField')).toBe('Some new field');
    });
  });

  describe('formatValue', () => {
    it('resolves ids to names', () => {
      expect(formatValue('currentLocationId', 1, lookups)).toBe('Mulberry');
      expect(formatValue('departmentId', 7, lookups)).toBe('WELD');
      expect(formatValue('trailerModelId', 192, lookups)).toBe('15TLT20');
      expect(formatValue('customerId', '78', lookups)).toBe("Amy's Bird Sanctuary");
    });

    it('falls back readably when the id is unknown', () => {
      expect(formatValue('currentLocationId', 99, lookups)).toBe('Location #99');
    });

    it('renders enums, booleans and the priority sentinel', () => {
      expect(formatValue('status', 'ready_for_delivery')).toBe('Ready for delivery');
      expect(formatValue('isHot', true)).toBe('Yes');
      expect(formatValue('isHot', false)).toBe('No');
      expect(formatValue('globalPriority', 9999)).toBe('Normal');
      expect(formatValue('globalPriority', 3)).toBe('3');
    });

    it('treats empty as no value', () => {
      expect(formatValue('soldToName', null)).toBeNull();
      expect(formatValue('soldToName', '')).toBeNull();
    });
  });

  describe('diffFields', () => {
    it('reports EVERY changed field, not just a hard-coded few', () => {
      const changes = diffFields(
        { status: 'in_production', color: 'Black', sizeFt: '16' },
        { status: 'ready_for_delivery', color: 'White', sizeFt: '16' },
        lookups,
      );
      // sizeFt did not change; the other two did.
      expect(changes).toEqual([
        { field: 'Status', from: 'In production', to: 'Ready for delivery' },
        { field: 'Color', from: 'Black', to: 'White' },
      ]);
    });

    it('ignores noise that changes on every write', () => {
      const changes = diffFields(
        { updatedAt: '2026-01-01T00:00:00Z', status: 'ready' },
        { updatedAt: '2026-01-02T00:00:00Z', status: 'ready' },
      );
      expect(changes).toEqual([]);
    });

    it('reports a create as "set to"', () => {
      const changes = diffFields(null, { status: 'pending_production' });
      expect(changes).toEqual([
        { field: 'Status', from: null, to: 'Pending production' },
      ]);
    });
  });

  describe('summarize', () => {
    it('spells out a single change instead of saying "Updated"', () => {
      const changes = diffFields(
        { status: 'in_production' },
        { status: 'ready_for_delivery' },
      );
      expect(summarize('UPDATE', 'trailer', {}, {}, changes)).toBe(
        'Status: In production → Ready for delivery',
      );
    });

    it('summarises many changes without hiding them', () => {
      const changes = diffFields(
        { status: 'a_b', color: 'Black', sizeFt: '16' },
        { status: 'c_d', color: 'White', sizeFt: '20' },
      );
      expect(summarize('UPDATE', 'trailer', {}, {}, changes)).toContain('+2 more changes');
      expect(changes).toHaveLength(3); // the full list still travels to the UI
    });

    it('describes QC by its result, not the verb', () => {
      expect(
        summarize('CREATE', 'qc_inspection', null, { result: 'fail', attemptNumber: 2, reworkTargetDeptCode: 'WELD' }, []),
      ).toBe('QC failed (attempt 2) — sent back to WELD');
      expect(
        summarize('CREATE', 'qc_inspection', null, { result: 'pass' }, []),
      ).toBe('QC passed');
    });

    it('falls back to the verb only when there is truly nothing to say', () => {
      expect(summarize('DELETE', 'trailer', null, null, [])).toBe('Deleted');
    });
  });
});
