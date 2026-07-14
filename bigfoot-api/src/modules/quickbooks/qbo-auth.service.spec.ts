import { ConfigService } from '@nestjs/config';
import { QboAuthService } from './qbo-auth.service';
import { AppError } from '../../common/errors';

/**
 * Unit tests for the QBO OAuth token lifecycle — the one piece of Slice 0
 * with real logic worth guarding: refresh-before-expiry, persistence shape,
 * and the "not connected" guard. `fetch` and Prisma are mocked; no network.
 */
describe('QboAuthService', () => {
  const env: Record<string, string> = {
    QBO_CLIENT_ID: 'client-abc',
    QBO_CLIENT_SECRET: 'secret-xyz',
    QBO_REDIRECT_URI: 'https://example.test/v1/quickbooks/callback',
    QBO_ENVIRONMENT: 'sandbox',
  };
  const config = {
    get: <T>(k: string): T => env[k] as unknown as T,
  } as unknown as ConfigService;

  let prisma: {
    qboAuthToken: {
      findFirst: jest.Mock;
      upsert: jest.Mock;
      delete: jest.Mock;
    };
  };
  let service: QboAuthService;
  let fetchMock: jest.Mock;

  beforeEach(() => {
    prisma = {
      qboAuthToken: {
        findFirst: jest.fn(),
        upsert: jest.fn(),
        delete: jest.fn(),
      },
    };
    service = new QboAuthService(config, prisma as never);
    fetchMock = jest.fn();
    (globalThis as unknown as { fetch: jest.Mock }).fetch = fetchMock;
  });

  it('builds a consent URL with client id, redirect, scope and state', () => {
    const url = service.getAuthorizationUrl('nonce.sig');
    expect(url).toContain('https://appcenter.intuit.com/connect/oauth2');
    expect(url).toContain('client_id=client-abc');
    expect(url).toContain('response_type=code');
    expect(url).toContain('scope=com.intuit.quickbooks.accounting');
    expect(url).toContain('state=nonce.sig');
  });

  it('throws SERVICE_UNAVAILABLE when no realm is connected', async () => {
    prisma.qboAuthToken.findFirst.mockResolvedValue(null);
    await expect(service.getValidAccessToken()).rejects.toBeInstanceOf(AppError);
  });

  it('returns the stored access token when it is comfortably valid', async () => {
    prisma.qboAuthToken.findFirst.mockResolvedValue({
      realmId: 'realm-1',
      accessToken: 'still-good',
      refreshToken: 'refresh-1',
      // 1 hour out — well past the 5-min skew.
      accessExpiresAt: new Date(Date.now() + 60 * 60 * 1000),
      refreshExpiresAt: new Date(Date.now() + 100 * 24 * 3600 * 1000),
    });

    const { accessToken, realmId } = await service.getValidAccessToken();

    expect(accessToken).toBe('still-good');
    expect(realmId).toBe('realm-1');
    expect(fetchMock).not.toHaveBeenCalled(); // no refresh needed
  });

  it('refreshes when the access token is within the skew window', async () => {
    prisma.qboAuthToken.findFirst.mockResolvedValue({
      realmId: 'realm-1',
      accessToken: 'about-to-expire',
      refreshToken: 'refresh-1',
      // 2 min out — inside the 5-min skew, so it must refresh.
      accessExpiresAt: new Date(Date.now() + 2 * 60 * 1000),
      refreshExpiresAt: new Date(Date.now() + 100 * 24 * 3600 * 1000),
    });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        access_token: 'freshly-refreshed',
        refresh_token: 'refresh-2',
        expires_in: 3600,
        x_refresh_token_expires_in: 8640000,
        token_type: 'bearer',
      }),
    });
    prisma.qboAuthToken.upsert.mockImplementation(({ create }: never) => create);

    const { accessToken } = await service.getValidAccessToken();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    // Token endpoint hit with a refresh_token grant + Basic auth.
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toContain('/oauth2/v1/tokens/bearer');
    expect(init.body).toContain('grant_type=refresh_token');
    expect(init.headers.Authorization).toMatch(/^Basic /);
    expect(accessToken).toBe('freshly-refreshed');
    // Persisted the rotated pair.
    expect(prisma.qboAuthToken.upsert).toHaveBeenCalledTimes(1);
  });

  it('exchanges an auth code and persists the token pair on callback', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        access_token: 'acc-1',
        refresh_token: 'ref-1',
        expires_in: 3600,
        x_refresh_token_expires_in: 8640000,
        token_type: 'bearer',
      }),
    });
    prisma.qboAuthToken.upsert.mockResolvedValue({});

    await service.handleCallback('the-code', 'realm-9');

    const [, init] = fetchMock.mock.calls[0];
    expect(init.body).toContain('grant_type=authorization_code');
    expect(init.body).toContain('code=the-code');
    expect(prisma.qboAuthToken.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { realmId: 'realm-9' } }),
    );
  });

  it('surfaces a typed error when the token endpoint fails', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 400,
      text: async () => 'invalid_grant',
    });
    await expect(service.handleCallback('bad', 'realm-1')).rejects.toBeInstanceOf(
      AppError,
    );
  });

  it('reports disconnected status when no token row exists', async () => {
    prisma.qboAuthToken.findFirst.mockResolvedValue(null);
    const status = await service.status();
    expect(status).toEqual({ connected: false, environment: 'sandbox' });
  });
});
