import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import {
  CurrentUser,
  JwtPayload,
} from '../../common/decorators/current-user.decorator';
import { AnnouncementsService } from './announcements.service';
import { CreateAnnouncementDto, UpdateAnnouncementDto } from './dto';

@ApiTags('Announcements')
@ApiBearerAuth('JWT')
@Controller()
export class AnnouncementsController {
  constructor(private readonly service: AnnouncementsService) {}

  // ---------------------------------------------------------------------------
  // GET /announcements/pending — every authenticated user
  // ---------------------------------------------------------------------------
  @Get('announcements/pending')
  @ApiOperation({
    summary:
      'Active, unexpired announcements the caller has not yet acknowledged, oldest first.',
  })
  @ApiResponse({ status: 200, description: 'Array of pending announcements' })
  async getPending(@CurrentUser() user: JwtPayload) {
    return this.service.getPendingForUser(BigInt(user.sub));
  }

  // ---------------------------------------------------------------------------
  // POST /announcements/:id/ack — every authenticated user
  // ---------------------------------------------------------------------------
  @Post('announcements/:id/ack')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Acknowledge an announcement on behalf of the caller.' })
  @ApiParam({ name: 'id', type: Number })
  @ApiResponse({ status: 200, description: 'Acknowledged (or already acked)' })
  @ApiResponse({ status: 404, description: 'Announcement not found' })
  async ack(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.ack(BigInt(id), BigInt(user.sub));
  }

  // ---------------------------------------------------------------------------
  // POST /admin/announcements — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post('admin/announcements')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
  )
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Publish a new announcement to every user.' })
  @ApiResponse({ status: 201, description: 'Announcement created' })
  async create(
    @Body() dto: CreateAnnouncementDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.create(dto, BigInt(user.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /admin/announcements — owner + production_manager
  // ---------------------------------------------------------------------------
  @Get('admin/announcements')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
  )
  @ApiOperation({
    summary:
      'List every announcement with ack counts so the admin screen can show "X of Y acknowledged".',
  })
  @ApiResponse({ status: 200, description: 'Announcements with ack stats' })
  async findAll() {
    return this.service.findAllForAdmin();
  }

  // ---------------------------------------------------------------------------
  // PATCH /admin/announcements/:id — owner + production_manager
  // ---------------------------------------------------------------------------
  @Patch('admin/announcements/:id')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
  )
  @ApiOperation({ summary: 'Edit / deactivate / re-expire an announcement.' })
  @ApiParam({ name: 'id', type: Number })
  @ApiResponse({ status: 200, description: 'Announcement updated' })
  @ApiResponse({ status: 404, description: 'Announcement not found' })
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateAnnouncementDto,
  ) {
    return this.service.update(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // DELETE /admin/announcements/:id — owner + production_manager
  // ---------------------------------------------------------------------------
  @Delete('admin/announcements/:id')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
  )
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary:
      'Hard-delete an announcement and its ack history. Use isActive=false on the PATCH to keep the trail.',
  })
  @ApiParam({ name: 'id', type: Number })
  @ApiResponse({ status: 200, description: 'Announcement deleted' })
  @ApiResponse({ status: 404, description: 'Announcement not found' })
  async remove(@Param('id', ParseIntPipe) id: number) {
    return this.service.remove(BigInt(id));
  }
}
