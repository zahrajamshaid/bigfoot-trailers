import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { NotificationsGateway } from './notifications.gateway';
import { NotificationsService } from './notifications.service';
import { PushService } from './push.service';
import { SmsService } from './sms.service';
import { MessagesService } from './messages.service';
import { MessagesController } from './messages.controller';
import { NotificationsController } from './notifications.controller';

@Module({
  imports: [
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_SECRET'),
      }),
    }),
  ],
  controllers: [MessagesController, NotificationsController],
  providers: [
    NotificationsGateway,
    NotificationsService,
    PushService,
    SmsService,
    MessagesService,
  ],
  exports: [NotificationsService, SmsService, PushService, NotificationsGateway],
})
export class NotificationsModule {}
