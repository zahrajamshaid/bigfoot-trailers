import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AnnouncementsService } from './announcements.service';

const mockPrisma = {
  systemAnnouncement: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
  },
  systemAnnouncementAck: {
    upsert: jest.fn(),
  },
  user: {
    count: jest.fn(),
  },
};

/// Build a findMany row for getPendingForUser. `ackedAt` null → never acked.
function pendingRow(id: number, frequency: string, ackedAt: Date | null) {
  return {
    id: BigInt(id),
    title: `t${id}`,
    body: `b${id}`,
    frequency,
    createdAt: new Date('2026-01-01T00:00:00Z'),
    postedByUser: { fullName: 'Owner' },
    acks: ackedAt ? [{ ackedAt }] : [],
  };
}

describe('AnnouncementsService', () => {
  let service: AnnouncementsService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [AnnouncementsService, { provide: PrismaService, useValue: mockPrisma }],
    }).compile();

    service = module.get<AnnouncementsService>(AnnouncementsService);
    jest.clearAllMocks();
  });

  describe('getPendingForUser', () => {
    it('queries active + unexpired, oldest first, joining this user’s ack', async () => {
      mockPrisma.systemAnnouncement.findMany.mockResolvedValue([]);

      await service.getPendingForUser(BigInt(7));

      const call = mockPrisma.systemAnnouncement.findMany.mock.calls[0][0];
      expect(call.where).toMatchObject({ isActive: true });
      expect(call.where.OR).toEqual([
        { expiresAt: null },
        { expiresAt: { gt: expect.any(Date) } },
      ]);
      expect(call.orderBy).toEqual({ createdAt: 'asc' });
      // The per-user ack is joined so the frequency filter can run in code.
      expect(call.select.acks.where).toEqual({ userId: BigInt(7) });
    });

    it('applies the per-frequency recurrence rules and strips acks', async () => {
      const now = new Date();
      const yesterday = new Date(now.getTime() - 26 * 3600 * 1000);
      const eightDaysAgo = new Date(now.getTime() - 8 * 24 * 3600 * 1000);
      const anHourAgo = new Date(now.getTime() - 3600 * 1000);

      mockPrisma.systemAnnouncement.findMany.mockResolvedValue([
        pendingRow(1, 'once', null), // never acked → show
        pendingRow(2, 'once', anHourAgo), // acked → hide forever
        pendingRow(3, 'every_login', anHourAgo), // always show
        pendingRow(4, 'daily', anHourAgo), // acked today → hide
        pendingRow(5, 'daily', yesterday), // acked before today → show
        pendingRow(6, 'weekly', yesterday), // acked this week → hide
        pendingRow(7, 'weekly', eightDaysAgo), // acked >1wk ago → show
      ]);

      const result = await service.getPendingForUser(BigInt(7));
      const ids = result.map((r) => Number(r.id));

      expect(ids).toEqual([1, 3, 5, 7]);
      // Response shape stays slim — the joined acks are not leaked.
      expect((result[0] as any).acks).toBeUndefined();
    });
  });

  describe('ack', () => {
    it('upserts the ack (refreshing ackedAt) on ack', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncementAck.upsert.mockResolvedValue({});

      const result = await service.ack(BigInt(1), BigInt(9));

      expect(result).toEqual({ acked: true });
      const arg = mockPrisma.systemAnnouncementAck.upsert.mock.calls[0][0];
      expect(arg.where).toEqual({
        announcementId_userId: { announcementId: BigInt(1), userId: BigInt(9) },
      });
      expect(arg.create).toEqual({ announcementId: BigInt(1), userId: BigInt(9) });
      expect(arg.update.ackedAt).toBeInstanceOf(Date);
    });

    it('throws NOT_FOUND for unknown announcement', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue(null);

      await expect(service.ack(BigInt(999), BigInt(1))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  describe('create', () => {
    it('persists body + optional title + optional expiresAt + posted_by', async () => {
      mockPrisma.systemAnnouncement.create.mockResolvedValue({ id: BigInt(1) });

      await service.create(
        {
          title: ' Heads up ',
          body: ' Floor closes early ',
          expiresAt: '2026-07-01T18:00:00Z',
        },
        BigInt(10),
      );

      const callData = mockPrisma.systemAnnouncement.create.mock.calls[0][0].data;
      expect(callData.title).toBe('Heads up');
      expect(callData.body).toBe('Floor closes early');
      expect(callData.postedByUserId).toBe(BigInt(10));
      expect(callData.expiresAt).toBeInstanceOf(Date);
    });

    it('defaults frequency to "once" and persists an explicit one', async () => {
      mockPrisma.systemAnnouncement.create.mockResolvedValue({ id: BigInt(1) });

      await service.create({ body: 'A' }, BigInt(10));
      expect(mockPrisma.systemAnnouncement.create.mock.calls[0][0].data.frequency).toBe(
        'once',
      );

      await service.create({ body: 'B', frequency: 'daily' }, BigInt(10));
      expect(mockPrisma.systemAnnouncement.create.mock.calls[1][0].data.frequency).toBe(
        'daily',
      );
    });

    it('treats missing title as null', async () => {
      mockPrisma.systemAnnouncement.create.mockResolvedValue({ id: BigInt(1) });

      await service.create({ body: 'No title' }, BigInt(10));

      const callData = mockPrisma.systemAnnouncement.create.mock.calls[0][0].data;
      expect(callData.title).toBeNull();
      expect(callData.expiresAt).toBeNull();
    });
  });

  describe('findAllForAdmin', () => {
    it('joins per-announcement ack counts with the active-user total', async () => {
      mockPrisma.systemAnnouncement.findMany.mockResolvedValue([
        {
          id: BigInt(1),
          title: 't',
          body: 'b',
          postedByUserId: BigInt(10),
          isActive: true,
          expiresAt: null,
          createdAt: new Date(),
          postedByUser: { id: BigInt(10), fullName: 'Owner', email: 'o@x' },
          _count: { acks: 7 },
        },
      ]);
      mockPrisma.user.count.mockResolvedValue(12);

      const result = await service.findAllForAdmin();

      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({ ackCount: 7, totalUsers: 12 });
      expect((result[0] as any)._count).toBeUndefined();
    });
  });

  describe('update', () => {
    it('throws NOT_FOUND for missing row', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue(null);

      await expect(service.update(BigInt(1), { body: 'b' })).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('only sets the fields the caller actually sent', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncement.update.mockResolvedValue({ id: BigInt(1) });

      await service.update(BigInt(1), { isActive: false });

      const data = mockPrisma.systemAnnouncement.update.mock.calls[0][0].data;
      expect(data).toEqual({ isActive: false });
    });

    it('updates frequency when provided', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncement.update.mockResolvedValue({ id: BigInt(1) });

      await service.update(BigInt(1), { frequency: 'weekly' });

      expect(mockPrisma.systemAnnouncement.update.mock.calls[0][0].data).toEqual({
        frequency: 'weekly',
      });
    });
  });
});
