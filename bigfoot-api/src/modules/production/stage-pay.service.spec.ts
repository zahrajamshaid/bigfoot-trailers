import { StagePayService, RecordPayoutsParams } from './stage-pay.service';

function makeTx(roster: Array<{ slot: number; userId: bigint }> = [], existing = 0) {
  return {
    productionStepPayout: {
      count: jest.fn().mockResolvedValue(existing),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    stageCrewMember: {
      findMany: jest.fn().mockResolvedValue(roster),
    },
  } as any;
}

const base: RecordPayoutsParams = {
  stepId: BigInt(1),
  departmentId: 1,
  deptCode: 'XP_JIG',
  series: 'xp',
  sizeFt: '18',
  color: 'gray',
  completedByUserId: BigInt(50),
  isRework: false,
  payDollars: 120,
  workerSplit: null,
};

function rows(tx: any) {
  return tx.productionStepPayout.createMany.mock.calls[0]?.[0]?.data ?? [];
}

describe('StagePayService', () => {
  const svc = new StagePayService();

  it('single stage → one base payout to the completer', async () => {
    const tx = makeTx();
    await svc.recordPayouts(tx, base);
    const r = rows(tx);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ userId: BigInt(50), kind: 'base' });
    expect(Number(r[0].dollars)).toBe(120);
  });

  it('rework → no payouts', async () => {
    const tx = makeTx();
    await svc.recordPayouts(tx, { ...base, isRework: true });
    expect(tx.productionStepPayout.createMany).not.toHaveBeenCalled();
  });

  it('idempotent → skips if payouts already exist', async () => {
    const tx = makeTx([], 2);
    await svc.recordPayouts(tx, base);
    expect(tx.productionStepPayout.createMany).not.toHaveBeenCalled();
  });

  it('crew stage with roster → each member paid their slot rate', async () => {
    const tx = makeTx([
      { slot: 0, userId: BigInt(101) },
      { slot: 1, userId: BigInt(102) },
      { slot: 2, userId: BigInt(103) },
    ]);
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'GN_WELD',
      series: 'gooseneck_dump',
      payDollars: 665,
      workerSplit: [665, 500, 400],
    });
    const r = rows(tx);
    expect(r).toHaveLength(3);
    expect(r.map((x: any) => [x.userId, Number(x.dollars)])).toEqual([
      [BigInt(101), 665],
      [BigInt(102), 500],
      [BigInt(103), 400],
    ]);
  });

  it('crew stage with NO roster → completer gets the primary rate', async () => {
    const tx = makeTx([]); // no roster
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'GN_WELD',
      series: 'gooseneck_dump',
      payDollars: 665,
      workerSplit: [665, 500, 400],
    });
    const r = rows(tx);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ userId: BigInt(50) });
    expect(Number(r[0].dollars)).toBe(665);
  });

  it('>30ft adds prep / wood / paint bonuses by series', async () => {
    // Paint on a >30ft non-gooseneck → +$20
    let tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'PAINT_B',
      series: 'xp',
      sizeFt: '32',
      payDollars: 70,
    });
    let r = rows(tx);
    expect(r.find((x: any) => x.note?.includes('over 30ft paint'))).toBeTruthy();
    expect(r.reduce((s: number, x: any) => s + Number(x.dollars), 0)).toBe(90); // 70 + 20

    // Paint on a >30ft gooseneck → +$50
    tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'PAINT_B',
      series: 'gooseneck_dump',
      sizeFt: '34',
      payDollars: 150,
    });
    r = rows(tx);
    expect(r.reduce((s: number, x: any) => s + Number(x.dollars), 0)).toBe(200); // 150 + 50

    // Wood >30ft gooseneck → +$30
    tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'WOOD',
      series: 'gooseneck_dump',
      sizeFt: '33',
      payDollars: 95,
    });
    r = rows(tx);
    expect(r.reduce((s: number, x: any) => s + Number(x.dollars), 0)).toBe(125); // 95 + 30
  });

  it('non-gray paint doubles the paint pay', async () => {
    const tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'PAINT_B',
      series: 'xp',
      sizeFt: '18',
      color: 'Red',
      payDollars: 70,
    });
    const r = rows(tx);
    expect(r.find((x: any) => x.note === 'non-gray double paint')).toBeTruthy();
    expect(r.reduce((s: number, x: any) => s + Number(x.dollars), 0)).toBe(140); // 70 + 70
  });

  it('wire hydraulic jack + toolbox adjustments', async () => {
    const tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'WIRE',
      series: 'xp',
      payDollars: 50,
      adjustments: { hydraulicJack: 'double', toolbox: true },
    });
    const total = rows(tx).reduce((s: number, x: any) => s + Number(x.dollars), 0);
    expect(total).toBe(50 + 65 + 15); // base + double jack + toolbox
  });

  it('wood tire swaps × $25', async () => {
    const tx = makeTx();
    await svc.recordPayouts(tx, {
      ...base,
      deptCode: 'WOOD',
      series: 'xp',
      sizeFt: '18',
      payDollars: 60,
      adjustments: { tireSwaps: 2 },
    });
    const total = rows(tx).reduce((s: number, x: any) => s + Number(x.dollars), 0);
    expect(total).toBe(60 + 50); // base + 2×25
  });
});
