import { Test, TestingModule } from '@nestjs/testing';
import { MessagesController } from './messages.controller';
import { MessagesService } from './messages.service';

describe('MessagesController', () => {
  let controller: MessagesController;

  const mockMessagesService = {
    create: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [MessagesController],
      providers: [{ provide: MessagesService, useValue: mockMessagesService }],
    }).compile();

    controller = module.get<MessagesController>(MessagesController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('create delegates to service with BigInt userId', async () => {
    const dto = { trailerId: 100, toUserId: 20, messageText: 'Test message' };
    const requester = {
      sub: 10,
      email: 'worker@test.com',
      role: 'worker',
      departmentId: 1,
      iat: 0,
      exp: 0,
    };
    mockMessagesService.create.mockResolvedValue({ id: BigInt(1) });

    await controller.create(dto, requester);

    expect(mockMessagesService.create).toHaveBeenCalledWith(dto, BigInt(10));
  });
});
