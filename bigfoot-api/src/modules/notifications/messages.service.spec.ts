import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { MessagesService } from './messages.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from './notifications.service';

describe('MessagesService', () => {
  let service: MessagesService;

  const mockPrisma = {
    trailer: { findUnique: jest.fn() },
    user: { findUnique: jest.fn() },
    workerMessage: { create: jest.fn() },
  };

  const mockNotificationsService = {
    onWorkerMessage: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MessagesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: NotificationsService, useValue: mockNotificationsService },
      ],
    }).compile();

    service = module.get<MessagesService>(MessagesService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('create', () => {
    it('should create a worker message and send notification', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({
        id: BigInt(100),
        soNumber: 'SO-1001',
      });
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({
          id: BigInt(20),
          role: 'sales',
          fullName: 'Sales Person',
        }) // recipient
        .mockResolvedValueOnce({ fullName: 'John Worker' }); // sender
      mockPrisma.workerMessage.create.mockResolvedValue({
        id: BigInt(1),
        trailerId: BigInt(100),
        messageText: 'Need info on paint color',
        isRead: false,
        sentAt: new Date(),
        fromUser: { id: BigInt(10), fullName: 'John Worker' },
        toUser: { id: BigInt(20), fullName: 'Sales Person' },
        trailer: { id: BigInt(100), soNumber: 'SO-1001' },
      });
      mockNotificationsService.onWorkerMessage.mockResolvedValue(undefined);

      const result = await service.create(
        { trailerId: 100, toUserId: 20, messageText: 'Need info on paint color' },
        BigInt(10),
      );

      expect(result.id).toBe(BigInt(1));
      expect(mockPrisma.workerMessage.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(100),
            fromUserId: BigInt(10),
            toUserId: BigInt(20),
            messageText: 'Need info on paint color',
          }),
        }),
      );
      expect(mockNotificationsService.onWorkerMessage).toHaveBeenCalledWith(
        BigInt(20),
        BigInt(100),
        'SO-1001',
        'John Worker',
        'Need info on paint color',
      );
    });

    it('should throw NOT_FOUND if trailer not found', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.create({ trailerId: 999, toUserId: 20, messageText: 'Test' }, BigInt(10)),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });

    it('should throw NOT_FOUND if recipient not found', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({
        id: BigInt(100),
        soNumber: 'SO-1001',
      });
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.create(
          { trailerId: 100, toUserId: 999, messageText: 'Test' },
          BigInt(10),
        ),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });
});
