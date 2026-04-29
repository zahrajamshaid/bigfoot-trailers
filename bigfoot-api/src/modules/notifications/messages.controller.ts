import { Controller, Post, Body } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { MessagesService } from './messages.service';
import { CreateWorkerMessageDto } from './dto';

@ApiTags('Messages')
@Controller('messages')
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  @Post()
  @Roles(UserRole.WORKER, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  async create(
    @Body() dto: CreateWorkerMessageDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.messagesService.create(dto, BigInt(requester.sub));
  }
}
