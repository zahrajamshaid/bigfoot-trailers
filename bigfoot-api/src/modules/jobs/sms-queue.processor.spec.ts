import { Test, TestingModule } from '@nestjs/testing';
import { SmsQueueProcessor } from './sms-queue.processor';
import { SmsService } from '../notifications/sms.service';

describe('SmsQueueProcessor', () => {
  let processor: SmsQueueProcessor;

  const mockSmsService = {
    processQueuedMessages: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [SmsQueueProcessor, { provide: SmsService, useValue: mockSmsService }],
    }).compile();

    processor = module.get<SmsQueueProcessor>(SmsQueueProcessor);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(processor).toBeDefined();
  });

  describe('processQueue', () => {
    it('should call smsService.processQueuedMessages', async () => {
      mockSmsService.processQueuedMessages.mockResolvedValue(3);
      await processor.processQueue();
      expect(mockSmsService.processQueuedMessages).toHaveBeenCalled();
    });

    it('should handle errors gracefully', async () => {
      mockSmsService.processQueuedMessages.mockRejectedValue(new Error('DB error'));
      // Should not throw
      await processor.processQueue();
      expect(mockSmsService.processQueuedMessages).toHaveBeenCalled();
    });

    it('should not run concurrently', async () => {
      // Simulate a slow processing
      let resolve: () => void;
      const promise = new Promise<number>((r) => {
        resolve = () => r(1);
      });
      mockSmsService.processQueuedMessages.mockReturnValue(promise);

      // Start first run
      const run1 = processor.processQueue();

      // Second run should be skipped because first is still running
      await processor.processQueue();

      // Complete first run
      resolve!();
      await run1;

      expect(mockSmsService.processQueuedMessages).toHaveBeenCalledTimes(1);
    });
  });
});
