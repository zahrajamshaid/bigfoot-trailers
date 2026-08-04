import { Test, TestingModule } from '@nestjs/testing';
import { SupportService } from './support.service';
import { PrismaService } from '../../prisma/prisma.service';
import { PushService } from '../notifications/push.service';
import { ErrorCode } from '../../common/errors';

const mockPrisma: Record<string, any> = {
  supportTicket: {
    create: jest.fn(),
    findMany: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
    count: jest.fn(),
  },
  supportTicketMessage: { create: jest.fn() },
  user: { findUnique: jest.fn(), findMany: jest.fn() },
  $transaction: jest.fn(async (fn: any) =>
    typeof fn === 'function' ? fn(mockPrisma) : undefined,
  ),
};

const mockPush = {
  sendSupportTicketOpened: jest.fn(),
  sendSupportTicketReply: jest.fn(),
};

function ticketRow(over: Record<string, any> = {}) {
  return {
    id: BigInt(1),
    subject: 'App crashes',
    status: 'open',
    reporterUserId: BigInt(50),
    createdAt: new Date(),
    updatedAt: new Date(),
    reporter: { id: BigInt(50), fullName: 'Sally Sales', role: 'sales' },
    messages: [],
    ...over,
  };
}

describe('SupportService', () => {
  let service: SupportService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SupportService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: PushService, useValue: mockPush },
      ],
    }).compile();
    service = module.get(SupportService);
    jest.clearAllMocks();
  });

  describe('createTicket', () => {
    it('creates a ticket and notifies the admin tier (not the reporter)', async () => {
      mockPrisma.supportTicket.create.mockResolvedValue({
        id: BigInt(1),
        subject: 'App crashes',
      });
      mockPrisma.user.findUnique.mockResolvedValue({ fullName: 'Sally Sales' });
      mockPrisma.user.findMany.mockResolvedValue([
        { id: BigInt(10) },
        { id: BigInt(11) },
      ]);
      mockPrisma.supportTicket.findUnique.mockResolvedValue(ticketRow());

      await service.createTicket(BigInt(50), {
        subject: 'App crashes',
        body: 'It closes',
      });

      // admins looked up excluding the reporter
      expect(mockPrisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ id: { not: BigInt(50) } }),
        }),
      );
      expect(mockPush.sendSupportTicketOpened).toHaveBeenCalledWith(
        BigInt(1),
        'App crashes',
        'Sally Sales',
        [BigInt(10), BigInt(11)],
      );
    });
  });

  describe('listTickets', () => {
    it('admin sees ALL tickets (empty where)', async () => {
      mockPrisma.supportTicket.findMany.mockResolvedValue([]);
      await service.listTickets(BigInt(10), 'owner');
      expect(mockPrisma.supportTicket.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: {} }),
      );
    });

    it('non-admin sees only their own', async () => {
      mockPrisma.supportTicket.findMany.mockResolvedValue([]);
      await service.listTickets(BigInt(50), 'sales');
      expect(mockPrisma.supportTicket.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { reporterUserId: BigInt(50) } }),
      );
    });
  });

  describe('getTicket access control', () => {
    it('forbids a different non-admin user', async () => {
      mockPrisma.supportTicket.findUnique.mockResolvedValue(ticketRow());
      await expect(
        service.getTicket(BigInt(999), 'sales', BigInt(1)),
      ).rejects.toMatchObject({ errorCode: ErrorCode.FORBIDDEN });
    });

    it('allows the reporter', async () => {
      mockPrisma.supportTicket.findUnique.mockResolvedValue(ticketRow());
      const res = await service.getTicket(BigInt(50), 'sales', BigInt(1));
      expect(res.id).toBe('1');
    });

    it('allows an admin who is not the reporter', async () => {
      mockPrisma.supportTicket.findUnique.mockResolvedValue(ticketRow());
      const res = await service.getTicket(BigInt(10), 'production_manager', BigInt(1));
      expect(res.id).toBe('1');
    });
  });

  describe('addMessage', () => {
    it('reopens the ticket and notifies the reporter when an admin replies', async () => {
      mockPrisma.supportTicket.findUnique
        .mockResolvedValueOnce({
          id: BigInt(1),
          subject: 'App crashes',
          reporterUserId: BigInt(50),
          status: 'resolved',
        })
        .mockResolvedValueOnce(ticketRow()); // getTicket at the end
      mockPrisma.user.findUnique.mockResolvedValue({ fullName: 'Olivia Owner' });

      await service.addMessage(BigInt(10), 'owner', BigInt(1), { body: 'Fixed it' });

      expect(mockPrisma.supportTicket.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'open' }) }),
      );
      expect(mockPush.sendSupportTicketReply).toHaveBeenCalledWith(
        BigInt(1),
        'App crashes',
        'Olivia Owner',
        [BigInt(50)],
      );
    });

    it('forbids a stranger from posting', async () => {
      mockPrisma.supportTicket.findUnique.mockResolvedValue({
        id: BigInt(1),
        subject: 'x',
        reporterUserId: BigInt(50),
        status: 'open',
      });
      await expect(
        service.addMessage(BigInt(999), 'sales', BigInt(1), { body: 'hi' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.FORBIDDEN });
    });
  });

  describe('setStatus', () => {
    it('forbids a non-admin', async () => {
      await expect(
        service.setStatus(BigInt(50), 'sales', BigInt(1), 'resolved'),
      ).rejects.toMatchObject({ errorCode: ErrorCode.FORBIDDEN });
    });
  });
});
