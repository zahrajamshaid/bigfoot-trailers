import { Test, TestingModule } from '@nestjs/testing';
import { PrismaService } from '../../prisma/prisma.service';
import { ActivityService } from './activity.service';

const mockPrisma = {
  userActivityDaily: {
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    groupBy: jest.fn(),
    findMany: jest.fn(),
  },
  user: { findMany: jest.fn() },
};

describe('ActivityService', () => {
  let service: ActivityService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [ActivityService, { provide: PrismaService, useValue: mockPrisma }],
    }).compile();
    service = module.get<ActivityService>(ActivityService);
    jest.clearAllMocks();
  });

  describe('recordHeartbeat', () => {
    it('seeds a new day with the base heartbeat seconds', async () => {
      mockPrisma.userActivityDaily.findUnique.mockResolvedValue(null);
      mockPrisma.userActivityDaily.create.mockResolvedValue({});

      await service.recordHeartbeat(BigInt(5));

      const data = mockPrisma.userActivityDaily.create.mock.calls[0][0].data;
      expect(data.activeSeconds).toBe(60);
      expect(data.pingCount).toBe(1);
      expect(mockPrisma.userActivityDaily.update).not.toHaveBeenCalled();
    });

    it('adds the elapsed gap to an existing day', async () => {
      const last = new Date(Date.now() - 90 * 1000); // 90s ago
      mockPrisma.userActivityDaily.findUnique.mockResolvedValue({
        lastSeenAt: last,
      });
      mockPrisma.userActivityDaily.update.mockResolvedValue({});

      await service.recordHeartbeat(BigInt(5));

      const data = mockPrisma.userActivityDaily.update.mock.calls[0][0].data;
      // ~90s (allow ±2s for test timing)
      expect(data.activeSeconds.increment).toBeGreaterThanOrEqual(88);
      expect(data.activeSeconds.increment).toBeLessThanOrEqual(92);
      expect(data.pingCount.increment).toBe(1);
    });

    it('caps a long idle gap so overnight-open apps do not inflate usage', async () => {
      const last = new Date(Date.now() - 3 * 3600 * 1000); // 3h ago
      mockPrisma.userActivityDaily.findUnique.mockResolvedValue({
        lastSeenAt: last,
      });
      mockPrisma.userActivityDaily.update.mockResolvedValue({});

      await service.recordHeartbeat(BigInt(5));

      const data = mockPrisma.userActivityDaily.update.mock.calls[0][0].data;
      expect(data.activeSeconds.increment).toBe(150); // GAP_CAP_SECONDS
    });
  });

  describe('getSummary', () => {
    it('joins names, computes days-active + total time, busiest first', async () => {
      mockPrisma.userActivityDaily.groupBy.mockResolvedValue([
        {
          userId: BigInt(1),
          _sum: { activeSeconds: 600 },
          _count: { day: 2 },
          _max: { lastSeenAt: new Date('2026-08-12T16:00:00Z') },
        },
        {
          userId: BigInt(2),
          _sum: { activeSeconds: 4000 },
          _count: { day: 5 },
          _max: { lastSeenAt: new Date('2026-08-12T15:00:00Z') },
        },
      ]);
      mockPrisma.user.findMany.mockResolvedValue([
        { id: BigInt(1), fullName: 'Jane', role: 'sales' },
        { id: BigInt(2), fullName: 'Bob', role: 'worker' },
      ]);

      const res = await service.getSummary('2026-08-06', '2026-08-12');

      expect(res.users.map((u) => u.fullName)).toEqual(['Bob', 'Jane']); // sorted desc
      expect(res.users[0]).toMatchObject({
        totalActiveSeconds: 4000,
        daysActive: 5,
        role: 'worker',
      });
      expect(res.from).toBe('2026-08-06');
      expect(res.to).toBe('2026-08-12');
    });
  });

  describe('getUserDaily', () => {
    it('returns day-by-day rows with the day serialised to YYYY-MM-DD', async () => {
      mockPrisma.userActivityDaily.findMany.mockResolvedValue([
        {
          day: new Date('2026-08-12T00:00:00Z'),
          activeSeconds: 1200,
          firstSeenAt: new Date('2026-08-12T08:00:00Z'),
          lastSeenAt: new Date('2026-08-12T16:00:00Z'),
          pingCount: 40,
        },
      ]);

      const res = await service.getUserDaily(BigInt(2), '2026-08-06', '2026-08-12');

      expect(res.days).toHaveLength(1);
      expect(res.days[0]).toMatchObject({ day: '2026-08-12', activeSeconds: 1200 });
    });
  });
});
