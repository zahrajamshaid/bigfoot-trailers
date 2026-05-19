import {
  Controller,
  DefaultValuePipe,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { NotificationsService } from './notifications.service';

@ApiTags('Notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  @ApiBearerAuth('JWT')
  @ApiOperation({ summary: 'Get current user push notification history' })
  @ApiResponse({ status: 200, description: 'Notification history returned' })
  async getHistory(
    @CurrentUser() requester: JwtPayload,
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('limit', new DefaultValuePipe(100), ParseIntPipe) limit: number,
  ) {
    return this.notificationsService.getHistory(BigInt(requester.sub), page, limit);
  }

  @Delete(':id')
  @ApiBearerAuth('JWT')
  @ApiOperation({ summary: 'Delete a notification from the current user history' })
  @ApiResponse({ status: 200, description: 'Notification deleted' })
  @ApiResponse({ status: 404, description: 'Notification not found' })
  async delete(
    @CurrentUser() requester: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.notificationsService.deleteNotification(
      BigInt(requester.sub),
      BigInt(id),
    );
  }
}
