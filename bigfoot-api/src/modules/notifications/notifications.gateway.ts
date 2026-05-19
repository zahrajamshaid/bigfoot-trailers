import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Event type constants — the 11 spec events + WORKER_MESSAGE
// ---------------------------------------------------------------------------
export const WsEvent = {
  STEP_COMPLETED: 'STEP_COMPLETED',
  STEP_REVERSED: 'STEP_REVERSED',
  QC_PASS: 'QC_PASS',
  QC_FAIL: 'QC_FAIL',
  TRAILER_READY: 'TRAILER_READY',
  QUEUE_REORDERED: 'QUEUE_REORDERED',
  PRIORITY_CHANGED: 'PRIORITY_CHANGED',
  TRAILER_STALLED: 'TRAILER_STALLED',
  DELIVERY_DISPATCHED: 'DELIVERY_DISPATCHED',
  DELIVERY_COMPLETE: 'DELIVERY_COMPLETE',
  POINTS_UPDATED: 'POINTS_UPDATED',
  WORKER_MESSAGE: 'WORKER_MESSAGE',
} as const;

export type WsEventType = (typeof WsEvent)[keyof typeof WsEvent];

// ---------------------------------------------------------------------------
// Gateway
// ---------------------------------------------------------------------------
@WebSocketGateway({
  cors: {
    // Restrict WS origins in prod via CORS_ALLOWED_ORIGINS (comma-separated).
    // Defaults to "*" only if unset — callers must set this before prod deploy.
    origin: process.env['CORS_ALLOWED_ORIGINS']
      ? process.env['CORS_ALLOWED_ORIGINS'].split(',').map((s) => s.trim())
      : '*',
    credentials: true,
  },
  namespace: '/ws',
  pingInterval: 30000,
  pingTimeout: 10000,
})
export class NotificationsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(NotificationsGateway.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  // -------------------------------------------------------------------------
  // JWT Authentication on handshake
  // -------------------------------------------------------------------------
  async handleConnection(client: Socket) {
    try {
      const token =
        client.handshake.auth?.token ??
        client.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        this.logger.warn(`Client ${client.id} rejected — no token`);
        client.disconnect(true);
        return;
      }

      const secret = this.configService.get<string>('JWT_SECRET');
      const payload = this.jwtService.verify(token, { secret });

      // Attach user info to socket data
      client.data.userId = payload.sub;
      client.data.role = payload.role;
      client.data.departmentId = payload.departmentId;

      // Auto-join rooms based on user context
      // 1. User's personal room
      await client.join(`user:${payload.sub}`);

      // 2. Role-based room
      await client.join(`role:${payload.role}`);

      // 3. Department room (if assigned)
      if (payload.departmentId) {
        await client.join(`dept:${payload.departmentId}`);
      }

      // 4. Managers and owners join the alerts room
      const alertRoles = ['owner', 'production_manager', 'transport_manager'];
      if (alertRoles.includes(payload.role)) {
        await client.join('alerts');
      }

      this.logger.log(
        `Client ${client.id} connected — user:${payload.sub} role:${payload.role}`,
      );
    } catch {
      this.logger.warn(`Client ${client.id} rejected — invalid token`);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client ${client.id} disconnected`);
  }

  // -------------------------------------------------------------------------
  // Heartbeat — client sends "heartbeat", server responds with "heartbeat_ack"
  // -------------------------------------------------------------------------
  @SubscribeMessage('heartbeat')
  handleHeartbeat(client: Socket) {
    client.emit('heartbeat_ack', { timestamp: new Date().toISOString() });
  }

  // -------------------------------------------------------------------------
  // Room subscription — allow clients to join additional dept rooms
  // -------------------------------------------------------------------------
  @SubscribeMessage('subscribe')
  async handleSubscribe(client: Socket, payload: { room: string }) {
    if (!payload?.room) return;
    // Only allow dept: and alerts rooms for subscription
    if (payload.room.startsWith('dept:') || payload.room === 'alerts') {
      await client.join(payload.room);
      client.emit('subscribed', { room: payload.room });
    }
  }

  @SubscribeMessage('unsubscribe')
  async handleUnsubscribe(client: Socket, payload: { room: string }) {
    if (!payload?.room) return;
    await client.leave(payload.room);
    client.emit('unsubscribed', { room: payload.room });
  }

  // -------------------------------------------------------------------------
  // Emit helpers — called by NotificationsService
  // -------------------------------------------------------------------------

  /** Emit to a specific department room */
  emitToDepartment(departmentId: number, event: WsEventType, data: unknown) {
    this.server.to(`dept:${departmentId}`).emit(event, {
      event,
      channel: `dept:${departmentId}`,
      data,
      timestamp: new Date().toISOString(),
    });
  }

  /** Emit to the global alerts room */
  emitToAlerts(event: WsEventType, data: unknown) {
    this.server.to('alerts').emit(event, {
      event,
      channel: 'alerts',
      data,
      timestamp: new Date().toISOString(),
    });
  }

  /** Emit to a specific user */
  emitToUser(userId: number | bigint, event: WsEventType, data: unknown) {
    this.server.to(`user:${userId}`).emit(event, {
      event,
      channel: `user:${userId}`,
      data,
      timestamp: new Date().toISOString(),
    });
  }

  /** Emit to a role-based room */
  emitToRole(role: string, event: WsEventType, data: unknown) {
    this.server.to(`role:${role}`).emit(event, {
      event,
      channel: `role:${role}`,
      data,
      timestamp: new Date().toISOString(),
    });
  }
}
