/**
 * E2E Auth Helpers — create test users and obtain JWT tokens.
 */
import * as bcrypt from 'bcrypt';
import * as request from 'supertest';
import { PrismaService } from '../../src/prisma/prisma.service';

const BCRYPT_ROUNDS = 10; // Faster than prod (12) for test speed
const DEFAULT_PASSWORD = 'TestPass123!';

export interface TestUser {
  id: bigint;
  email: string;
  role: string;
  token: string;
}

/**
 * Creates a user directly in the database with a bcrypt-hashed password.
 * Emails use @e2e.test domain for easy cleanup identification.
 */
export async function createTestUser(
  prisma: PrismaService,
  overrides: {
    email?: string;
    fullName?: string;
    role?: string;
    primaryDepartmentId?: number | null;
  } = {},
): Promise<{ id: bigint; email: string }> {
  const email =
    overrides.email ??
    `user-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@e2e.test`;
  const passwordHash = await bcrypt.hash(DEFAULT_PASSWORD, BCRYPT_ROUNDS);

  const user = await prisma.user.create({
    data: {
      email,
      fullName: overrides.fullName ?? 'E2E Test User',
      passwordHash,
      role: (overrides.role ?? 'owner') as any,
      primaryDepartmentId: overrides.primaryDepartmentId ?? null,
    },
    select: { id: true, email: true },
  });

  return { id: user.id, email: user.email! };
}

/**
 * Logs in via the auth endpoint and returns the JWT access token.
 */
export async function loginAs(
  httpServer: any,
  email: string,
  password: string = DEFAULT_PASSWORD,
): Promise<string> {
  const res = await request(httpServer)
    .post('/v1/auth/login')
    .send({ email, password })
    .expect(200);

  return res.body.data.accessToken;
}

/**
 * Creates a user + logs in in one call.  Returns a TestUser with a live JWT.
 */
export async function createAndLogin(
  prisma: PrismaService,
  httpServer: any,
  role: string,
  extra?: {
    fullName?: string;
    email?: string;
    primaryDepartmentId?: number | null;
  },
): Promise<TestUser> {
  const user = await createTestUser(prisma, { role, ...extra });
  const token = await loginAs(httpServer, user.email);
  return { id: user.id, email: user.email, role, token };
}
