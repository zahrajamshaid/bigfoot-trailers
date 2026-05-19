import { Test, TestingModule } from '@nestjs/testing';
import { NotificationsService } from './notifications.service';
import { PushService } from './push.service';
import { SmsService } from './sms.service';
import { NotificationsGateway, WsEvent } from './notifications.gateway';
import { PrismaService } from '../../prisma/prisma.service';

describe('NotificationsService', () => {
  let service: NotificationsService;

  const mockGateway = {
    emitToDepartment: jest.fn(),
    emitToAlerts: jest.fn(),
    emitToUser: jest.fn(),
    emitToRole: jest.fn(),
  };

  const mockPushService = {
    send: jest.fn(),
    sendQcFail: jest.fn(),
    sendTrailerStalled: jest.fn(),
    sendWorkerMessage: jest.fn(),
    sendPaymentNotCollected: jest.fn(),
  };

  const mockSmsService = {
    queueSms: jest.fn(),
  };

  const mockPrisma = {
    pushNotification: {
      findMany: jest.fn(),
      count: jest.fn(),
      deleteMany: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        NotificationsService,
        { provide: NotificationsGateway, useValue: mockGateway },
        { provide: PushService, useValue: mockPushService },
        { provide: SmsService, useValue: mockSmsService },
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<NotificationsService>(NotificationsService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // =========================================================================
  // STEP_COMPLETED
  // =========================================================================
  describe('onStepCompleted', () => {
    it('should emit to completing dept and next dept', async () => {
      await service.onStepCompleted({
        stepId: BigInt(1),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        departmentId: 1,
        departmentName: 'XP Jig Weld',
        nextStepId: BigInt(2),
        nextDepartmentId: 15,
        nextDepartmentName: 'QC 1',
        completedByUserId: BigInt(10),
        pointsAwarded: 3.5,
      });

      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        1,
        WsEvent.STEP_COMPLETED,
        expect.objectContaining({ soNumber: 'SO-1001' }),
      );
      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        15,
        WsEvent.STEP_COMPLETED,
        expect.any(Object),
      );
    });

    it('should skip next dept emit if no next department', async () => {
      await service.onStepCompleted({
        stepId: BigInt(1),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        departmentId: 1,
        departmentName: 'XP Jig Weld',
        nextStepId: null,
        nextDepartmentId: null,
        nextDepartmentName: null,
        completedByUserId: BigInt(10),
        pointsAwarded: 0,
      });

      expect(mockGateway.emitToDepartment).toHaveBeenCalledTimes(1);
    });
  });

  // =========================================================================
  // STEP_REVERSED
  // =========================================================================
  describe('onStepReversed', () => {
    it('should emit to the department', async () => {
      await service.onStepReversed({
        stepId: BigInt(1),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        departmentId: 1,
        departmentName: 'XP Jig Weld',
        reversedByUserId: BigInt(10),
      });

      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        1,
        WsEvent.STEP_REVERSED,
        expect.objectContaining({ soNumber: 'SO-1001' }),
      );
    });
  });

  // =========================================================================
  // QC_PASS
  // =========================================================================
  describe('onQcPass', () => {
    it('should emit to QC dept and next production dept', async () => {
      await service.onQcPass({
        inspectionId: BigInt(500),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        qcStep: 'QC_1',
        qcDepartmentId: 15,
        nextStepId: BigInt(3),
        nextDepartmentId: 2,
        nextDepartmentName: 'XP Finish Weld',
        isFinalQc: false,
        trailerStatus: 'in_production',
      });

      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        15,
        WsEvent.QC_PASS,
        expect.objectContaining({ qcStep: 'QC_1' }),
      );
      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        2,
        WsEvent.QC_PASS,
        expect.any(Object),
      );
      expect(mockGateway.emitToAlerts).not.toHaveBeenCalledWith(
        WsEvent.TRAILER_READY,
        expect.any(Object),
      );
    });

    it('should emit TRAILER_READY on final QC pass', async () => {
      await service.onQcPass({
        inspectionId: BigInt(500),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        qcStep: 'FINAL_QC',
        qcDepartmentId: 20,
        nextStepId: null,
        nextDepartmentId: null,
        nextDepartmentName: null,
        isFinalQc: true,
        trailerStatus: 'ready_for_delivery',
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.TRAILER_READY,
        expect.objectContaining({
          soNumber: 'SO-1001',
          trailerStatus: 'ready_for_delivery',
        }),
      );
    });
  });

  // =========================================================================
  // QC_FAIL — fires on BOTH target dept AND alerts + push
  // =========================================================================
  describe('onQcFail', () => {
    it('should emit to target dept AND alerts, then send push', async () => {
      mockPushService.sendQcFail.mockResolvedValue(undefined);

      await service.onQcFail({
        inspectionId: BigInt(567),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        qcStep: 'QC_3',
        qcDepartmentId: 17,
        failNotes: 'Paint bubbling near left fender',
        reworkTargetDeptId: 1,
        reworkTargetDepartment: 'XP Jig Weld',
        reworkStepId: BigInt(412),
      });

      // WebSocket: target dept
      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        1,
        WsEvent.QC_FAIL,
        expect.objectContaining({
          qcStep: 'QC_3',
          failNotes: 'Paint bubbling near left fender',
          reworkTargetDeptId: 1,
          soNumber: 'SO-1001',
        }),
      );

      // WebSocket: alerts
      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.QC_FAIL,
        expect.objectContaining({
          reworkTargetDepartment: 'XP Jig Weld',
        }),
      );

      // Push notification
      expect(mockPushService.sendQcFail).toHaveBeenCalledWith(
        BigInt(100),
        'SO-1001',
        'QC_3',
        'Paint bubbling near left fender',
        'XP Jig Weld',
        1,
      );
    });
  });

  // =========================================================================
  // QUEUE_REORDERED
  // =========================================================================
  describe('onQueueReordered', () => {
    it('should emit to the department', () => {
      service.onQueueReordered({ departmentId: 3, departmentName: 'Paint Prep' });
      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        3,
        WsEvent.QUEUE_REORDERED,
        expect.objectContaining({ departmentId: 3 }),
      );
    });
  });

  // =========================================================================
  // PRIORITY_CHANGED
  // =========================================================================
  describe('onPriorityChanged', () => {
    it('should emit to alerts', () => {
      service.onPriorityChanged({
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        globalPriority: 1,
        isHot: true,
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.PRIORITY_CHANGED,
        expect.objectContaining({ isHot: true }),
      );
    });
  });

  // =========================================================================
  // TRAILER_STALLED
  // =========================================================================
  describe('onTrailerStalled', () => {
    it('should emit to alerts + dept, then push', async () => {
      mockPushService.sendTrailerStalled.mockResolvedValue(undefined);

      await service.onTrailerStalled({
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        departmentId: 9,
        departmentName: 'Paint Prep',
        hoursStalled: 52.5,
        stallAlertId: BigInt(1),
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.TRAILER_STALLED,
        expect.objectContaining({ hoursStalled: 52.5 }),
      );
      expect(mockGateway.emitToDepartment).toHaveBeenCalledWith(
        9,
        WsEvent.TRAILER_STALLED,
        expect.any(Object),
      );
      expect(mockPushService.sendTrailerStalled).toHaveBeenCalledWith(
        BigInt(100),
        'SO-1001',
        'Paint Prep',
        52.5,
      );
    });
  });

  // =========================================================================
  // DELIVERY_DISPATCHED
  // =========================================================================
  describe('onDeliveryDispatched', () => {
    it('should emit to alerts and driver user', () => {
      service.onDeliveryDispatched({
        deliveryId: BigInt(50),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        driverUserId: BigInt(20),
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.DELIVERY_DISPATCHED,
        expect.objectContaining({ soNumber: 'SO-1001' }),
      );
      expect(mockGateway.emitToUser).toHaveBeenCalledWith(
        BigInt(20),
        WsEvent.DELIVERY_DISPATCHED,
        expect.any(Object),
      );
    });

    it('should not emit to user if no driver', () => {
      service.onDeliveryDispatched({
        deliveryId: BigInt(50),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        driverUserId: null,
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalled();
      expect(mockGateway.emitToUser).not.toHaveBeenCalled();
    });
  });

  // =========================================================================
  // DELIVERY_COMPLETE
  // =========================================================================
  describe('onDeliveryComplete', () => {
    it('should emit to alerts', async () => {
      mockPushService.sendPaymentNotCollected.mockResolvedValue(undefined);

      await service.onDeliveryComplete({
        deliveryId: BigInt(50),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        balanceDue: '5000.00',
        paymentCollected: '5000.00',
      });

      expect(mockGateway.emitToAlerts).toHaveBeenCalledWith(
        WsEvent.DELIVERY_COMPLETE,
        expect.objectContaining({ soNumber: 'SO-1001' }),
      );
      // Fully paid — no payment_not_collected push
      expect(mockPushService.sendPaymentNotCollected).not.toHaveBeenCalled();
    });

    it('should send payment_not_collected push when underpaid', async () => {
      mockPushService.sendPaymentNotCollected.mockResolvedValue(undefined);

      await service.onDeliveryComplete({
        deliveryId: BigInt(50),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        balanceDue: '5000.00',
        paymentCollected: '1000.00',
      });

      expect(mockPushService.sendPaymentNotCollected).toHaveBeenCalledWith(
        BigInt(100),
        'SO-1001',
        '5000.00',
        '1000.00',
      );
    });
  });

  // =========================================================================
  // POINTS_UPDATED
  // =========================================================================
  describe('onPointsUpdated', () => {
    it('should emit to the user', () => {
      service.onPointsUpdated({
        userId: BigInt(10),
        trailerId: BigInt(100),
        soNumber: 'SO-1001',
        departmentName: 'XP Jig Weld',
        pointsAwarded: 3.5,
      });

      expect(mockGateway.emitToUser).toHaveBeenCalledWith(
        BigInt(10),
        WsEvent.POINTS_UPDATED,
        expect.objectContaining({ pointsAwarded: 3.5 }),
      );
    });
  });

  // =========================================================================
  // WORKER_MESSAGE
  // =========================================================================
  describe('onWorkerMessage', () => {
    it('should emit to user and send push', async () => {
      mockPushService.sendWorkerMessage.mockResolvedValue(undefined);

      await service.onWorkerMessage(
        BigInt(20),
        BigInt(100),
        'SO-1001',
        'John Worker',
        'Need more paint',
      );

      expect(mockGateway.emitToUser).toHaveBeenCalledWith(
        BigInt(20),
        WsEvent.WORKER_MESSAGE,
        expect.objectContaining({
          soNumber: 'SO-1001',
          fromUserName: 'John Worker',
          messageText: 'Need more paint',
        }),
      );
      expect(mockPushService.sendWorkerMessage).toHaveBeenCalledWith(
        BigInt(20),
        BigInt(100),
        'SO-1001',
        'John Worker',
        'Need more paint',
      );
    });
  });
});
