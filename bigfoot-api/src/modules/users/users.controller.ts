import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
  ParseIntPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
} from '@nestjs/swagger';
import { UsersService } from './users.service';
import { CreateUserDto, UpdateUserDto, QueryUsersDto } from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Users')
@ApiBearerAuth('JWT')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  // ---------------------------------------------------------------------------
  // GET /users — owner and production_manager only
  // ---------------------------------------------------------------------------
  @Get()
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'List all users with pagination and filters' })
  @ApiResponse({ status: 200, description: 'Paginated user list' })
  @ApiResponse({ status: 403, description: 'Forbidden — insufficient role' })
  async findAll(@Query() query: QueryUsersDto) {
    return this.usersService.findAll(query);
  }

  // ---------------------------------------------------------------------------
  // POST /users — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post()
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new user (owner or production manager)' })
  @ApiResponse({ status: 201, description: 'User created' })
  @ApiResponse({ status: 409, description: 'Email already exists' })
  @ApiResponse({ status: 403, description: 'Forbidden — insufficient role' })
  async create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }

  // ---------------------------------------------------------------------------
  // GET /users/drivers — active drivers for delivery assignment
  // (transport_manager + owner; must be BEFORE the :id route)
  // ---------------------------------------------------------------------------
  @Get('drivers')
  @Roles(UserRole.OWNER, UserRole.TRANSPORT_MANAGER)
  @ApiOperation({ summary: 'List active drivers for delivery assignment' })
  @ApiResponse({ status: 200, description: 'Active drivers' })
  async findDrivers() {
    return this.usersService.findDrivers();
  }

  // ---------------------------------------------------------------------------
  // GET /users/:id
  // ---------------------------------------------------------------------------
  @Get(':id')
  @ApiOperation({ summary: 'Get a single user by ID' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'User detail with department and location' })
  @ApiResponse({ status: 404, description: 'User not found' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.findOne(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // PATCH /users/:id — owner can update everything, self can update limited fields
  // ---------------------------------------------------------------------------
  @Patch(':id')
  @ApiOperation({
    summary: 'Update user details (owner: all fields, self: name/phone/password)',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'User updated' })
  @ApiResponse({ status: 403, description: 'Forbidden' })
  @ApiResponse({ status: 404, description: 'User not found' })
  @ApiResponse({ status: 409, description: 'Email conflict' })
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.usersService.update(
      BigInt(id),
      dto,
      BigInt(requester.sub),
      requester.role,
    );
  }

  // ---------------------------------------------------------------------------
  // DELETE /users/:id — soft-delete, owner only
  // ---------------------------------------------------------------------------
  @Delete(':id')
  @Roles(UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Deactivate a user (soft-delete, owner only)' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'User deactivated' })
  @ApiResponse({
    status: 403,
    description: 'Forbidden — cannot delete last owner or self',
  })
  @ApiResponse({ status: 404, description: 'User not found' })
  async softDelete(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.usersService.softDelete(BigInt(id), BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // POST /users/:id/reactivate — undo a soft-delete (owner only)
  // ---------------------------------------------------------------------------
  @Post(':id/reactivate')
  @Roles(UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reactivate a previously deactivated user (owner only)' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'User reactivated' })
  @ApiResponse({ status: 400, description: 'User is already active' })
  @ApiResponse({ status: 404, description: 'User not found' })
  async reactivate(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.reactivate(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // DELETE /users/:id/permanent — hard-delete (owner only)
  // Only works on already-deactivated users with no historical activity.
  // ---------------------------------------------------------------------------
  @Delete(':id/permanent')
  @Roles(UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary:
      'Permanently delete a deactivated user (owner only). Refuses if the user has any historical activity.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'User permanently deleted' })
  @ApiResponse({
    status: 400,
    description: 'User still active or has historical activity',
  })
  @ApiResponse({ status: 404, description: 'User not found' })
  async hardDelete(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.usersService.hardDelete(BigInt(id), BigInt(requester.sub));
  }
}
