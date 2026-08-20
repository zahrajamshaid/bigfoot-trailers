import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { ActivityService } from './activity.service';
import { ActivityReportQueryDto } from './dto';

@ApiTags('Activity')
@ApiBearerAuth('JWT')
@Controller('activity')
export class ActivityController {
  constructor(private readonly service: ActivityService) {}

  // ---------------------------------------------------------------------------
  // POST /activity/heartbeat — every authenticated user (no @Roles).
  // ---------------------------------------------------------------------------
  @Post('heartbeat')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Record a foreground heartbeat for the current user (usage tracking).',
  })
  async heartbeat(@CurrentUser() user: JwtPayload) {
    return this.service.recordHeartbeat(BigInt(user.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /activity/summary — owner/office. Per-user usage over a date range.
  // ---------------------------------------------------------------------------
  @Get('summary')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @ApiOperation({
    summary: 'Daily active users + time-on-app over a date range (default: last 7 days).',
  })
  @ApiResponse({ status: 200, description: 'Per-user usage summary' })
  async summary(@Query() q: ActivityReportQueryDto) {
    return this.service.getSummary(q.from, q.to);
  }

  // ---------------------------------------------------------------------------
  // GET /activity/summary/:userId — owner/office. One user's day-by-day usage.
  // ---------------------------------------------------------------------------
  @Get('summary/:userId')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @ApiOperation({ summary: "A single user's day-by-day usage." })
  @ApiResponse({ status: 200, description: 'Daily usage rows' })
  async userDaily(
    @Param('userId', ParseIntPipe) userId: number,
    @Query() q: ActivityReportQueryDto,
  ) {
    return this.service.getUserDaily(BigInt(userId), q.from, q.to);
  }
}
