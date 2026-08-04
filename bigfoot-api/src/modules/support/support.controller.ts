import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  ParseIntPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiParam } from '@nestjs/swagger';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { SupportService } from './support.service';
import { CreateTicketDto, CreateMessageDto } from './dto';

@ApiTags('Support')
@Controller('support')
export class SupportController {
  constructor(private readonly support: SupportService) {}

  // Any authenticated user can raise a problem report — no @Roles gate.
  @Post('tickets')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Report a problem (creates a ticket + first message)' })
  @ApiResponse({ status: 201, description: 'Ticket created' })
  async create(@Body() dto: CreateTicketDto, @CurrentUser() user: JwtPayload) {
    return this.support.createTicket(BigInt(user.sub), dto);
  }

  // Admins see all tickets; everyone else sees only their own (service branches
  // on role, so no @Roles gate here).
  @Get('tickets')
  @ApiOperation({ summary: 'List tickets — all for admins, own for everyone else' })
  async list(@CurrentUser() user: JwtPayload) {
    const tickets = await this.support.listTickets(BigInt(user.sub), user.role);
    return { tickets };
  }

  // Count of open tickets — powers the admin dashboard badge.
  @Get('tickets/open-count')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Count of unresolved tickets (admin dashboard badge)' })
  async openCount() {
    return this.support.openCount();
  }

  @Get('tickets/:id')
  @ApiOperation({ summary: 'One ticket + its full thread (reporter or admin)' })
  @ApiParam({ name: 'id', type: 'number' })
  async getOne(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    return this.support.getTicket(BigInt(user.sub), user.role, BigInt(id));
  }

  @Post('tickets/:id/messages')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Reply on a ticket (reporter or admin)' })
  @ApiParam({ name: 'id', type: 'number' })
  async reply(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CreateMessageDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.support.addMessage(BigInt(user.sub), user.role, BigInt(id), dto);
  }

  @Patch('tickets/:id/resolve')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Mark a ticket resolved (admins)' })
  @ApiParam({ name: 'id', type: 'number' })
  async resolve(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    return this.support.setStatus(BigInt(user.sub), user.role, BigInt(id), 'resolved');
  }

  @Patch('tickets/:id/reopen')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Reopen a resolved ticket (admins)' })
  @ApiParam({ name: 'id', type: 'number' })
  async reopen(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    return this.support.setStatus(BigInt(user.sub), user.role, BigInt(id), 'open');
  }

  @Delete('tickets/:id')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Delete a ticket + its thread (admins)' })
  @ApiParam({ name: 'id', type: 'number' })
  async remove(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    return this.support.deleteTicket(user.role, BigInt(id));
  }
}
