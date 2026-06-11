import { Test, TestingModule } from '@nestjs/testing';
import { Prisma } from '@prisma/client';
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
    create: jest.fn(),
  },
  user: {
    count: jest.fn(),
  },
};

describe('AnnouncementsService', () => {
  let service: AnnouncementsService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AnnouncementsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<AnnouncementsService>(AnnouncementsService);
    jest.clearAllMocks();
  });

  describe('getPendingForUser', () => {
    it('filters to active + unexpired + not-acked-by-user, oldest first', async () => {
      mockPrisma.systemAnnouncement.findMany.mockResolvedValue([]);

      await service.getPendingForUser(BigInt(7));

      const call = mockPrisma.systemAnnouncement.findMany.mock.calls[0][0];
      expect(call.where).toMatchObject({
        isActive: true,
        acks: { none: { userId: BigInt(7) } },
      });
      expect(call.where.OR).toEqual([
        { expiresAt: null },
        { expiresAt: { gt: expect.any(Date) } },
      ]);
      expect(call.orderBy).toEqual({ createdAt: 'asc' });
    });
  });

  describe('ack', () => {
    it('creates an ack row on first call', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncementAck.create.mockResolvedValue({});

      const result = await service.ack(BigInt(1), BigInt(9));

      expect(result).toEqual({ acked: true });
      expect(mockPrisma.systemAnnouncementAck.create).toHaveBeenCalledWith({
        data: { announcementId: BigInt(1), userId: BigInt(9) },
      });
    });

    it('absorbs duplicate ack quietly via unique-constraint catch', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncementAck.create.mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError('dup', {
          code: 'P2002',
          clientVersion: 'test',
        }),
      );

      await expect(service.ack(BigInt(1), BigInt(9))).resolves.toEqual({
        acked: true,
      });
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
        { title: ' Heads up ', body: ' Floor closes early ', expiresAt: '2026-07-01T18:00:00Z' },
        BigInt(10),
      );

      const callData = mockPrisma.systemAnnouncement.create.mock.calls[0][0].data;
      expect(callData.title).toBe('Heads up');
      expect(callData.body).toBe('Floor closes early');
      expect(callData.postedByUserId).toBe(BigInt(10));
      expect(callData.expiresAt).toBeInstanceOf(Date);
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

      await expect(
        service.update(BigInt(1), { body: 'b' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });

    it('only sets the fields the caller actually sent', async () => {
      mockPrisma.systemAnnouncement.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.systemAnnouncement.update.mockResolvedValue({ id: BigInt(1) });

      await service.update(BigInt(1), { isActive: false });

      const data = mockPrisma.systemAnnouncement.update.mock.calls[0][0].data;
      expect(data).toEqual({ isActive: false });
    });
  });
});
