#!/usr/bin/env node

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const scannerUsername = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const scannerPassword = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const peerUsername = process.env.GENERIC_IM_SMOKE_PEER_USERNAME || 'h5peer';
const peerPassword = process.env.GENERIC_IM_SMOKE_PEER_PASSWORD || '123456';

async function main() {
  const scanner = await login(scannerUsername, scannerPassword, 'qr-scanner');
  const peer = await login(peerUsername, peerPassword, 'qr-peer');

  const userQr = await smokeUserQr(scanner, peer);
  const groupQr = await smokeGroupQr(scanner, peer);
  const loginQr = await smokeLoginQr(scanner);

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBase,
        scanner: {
          username: scannerUsername,
          uuid: scanner.user.uuid,
        },
        peer: {
          username: peerUsername,
          uuid: peer.user.uuid,
        },
        userQr,
        groupQr,
        loginQr,
      },
      null,
      2,
    ),
  );
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

function buildUserQrPayload(userUuid) {
  return `genericim://user/${userUuid}`;
}

function buildGroupQrPayload(inviteLink) {
  return `genericim://group/${inviteLink}`;
}

function buildLoginQrPayload(ticket) {
  return `genericim://login/${ticket}`;
}

function parseOneChatQrPayload(rawValue) {
  const raw = String(rawValue || '').trim();
  if (!raw) return null;
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol.toLowerCase() !== 'genericim:') return null;
  const id = url.pathname.split('/').filter(Boolean)[0] || '';
  if (!id) return null;
  switch (url.hostname.toLowerCase()) {
    case 'user':
      return { type: 'user', id };
    case 'group':
      return { type: 'group', id };
    case 'login':
      return { type: 'login', id };
    default:
      return null;
  }
}

async function login(username, password, label) {
  const json = await postJson('/api/v1/auth/login', {
    username,
    password,
    device_id: `web-qr-${label}-${Date.now()}`,
    device_type: 'web',
    device_name: `Flutter Web QR Smoke ${label}`,
  });
  const token = json?.data?.token;
  if (!token) {
    throw new Error(`Login failed for ${username}: ${JSON.stringify(json)}`);
  }
  const me = await getJson('/api/v1/user/me', token);
  const user = me?.data;
  if (!user?.uuid) {
    throw new Error(`Missing /user/me uuid for ${username}: ${JSON.stringify(me)}`);
  }
  return { token, user };
}

async function smokeUserQr(scanner, peer) {
  const raw = buildUserQrPayload(peer.user.uuid);
  const payload = assertPayload(raw, 'user');

  const scannedUser = await getJson(`/api/v1/user/${payload.id}`, scanner.token);
  if (scannedUser?.code !== 0 || !scannedUser?.data?.id) {
    throw new Error(`Scanned user lookup failed: ${JSON.stringify(scannedUser)}`);
  }

  const addContact = await postJson(
    '/api/v1/contact/add',
    { user_id: payload.id, remark: 'QR smoke peer' },
    scanner.token,
  );
  const addContactOk =
    addContact?.code === 0 || String(addContact?.message || '').includes('已经是联系人');
  if (!addContactOk) {
    throw new Error(`QR add contact failed: ${JSON.stringify(addContact)}`);
  }

  const privateChat = await postJson(
    '/api/v1/chat/create',
    { type: 1, member_ids: [payload.id] },
    scanner.token,
  );
  if (privateChat?.code !== 0 || !privateChat?.data?.uuid) {
    throw new Error(`QR private chat open failed: ${JSON.stringify(privateChat)}`);
  }

  return {
    raw,
    parsed: payload,
    scannedUser: {
      uuid: scannedUser.data.id,
      username: scannedUser.data.username,
      nickname: scannedUser.data.nickname,
    },
    addContactStatus: addContact.code === 0 ? 'added' : 'already_contact',
    chatId: privateChat.data.uuid,
  };
}

async function smokeGroupQr(scanner, peer) {
  const group = await createOrReuseQrGroup(peer);

  const raw = buildGroupQrPayload(group.inviteLink);
  const payload = assertPayload(raw, 'group');
  const joined = await postJson(
    `/api/v1/chat/invite/${encodeURIComponent(payload.id)}/join`,
    {},
    scanner.token,
  );
  if (joined?.code !== 0 || !joined?.data?.chat_id) {
    throw new Error(`QR group join failed: ${JSON.stringify(joined)}`);
  }

  return {
    raw,
    parsed: payload,
    source: group.source,
    createdChatId: group.chatId,
    inviteLink: group.inviteLink,
    joinedChatId: joined.data.chat_id,
    alreadyJoined: joined.data.already_joined === true,
    requiresApproval: joined.data.requires_approval === true,
    createFallbackReason: group.createFallbackReason,
  };
}

async function createOrReuseQrGroup(peer) {
  const groupName = `QR Smoke ${Date.now()}`;
  const created = await postJson(
    '/api/v1/chat/create',
    {
      type: 2,
      name: groupName,
      description: 'QR smoke group',
      member_ids: [],
      is_public: false,
    },
    peer.token,
  );
  if (created?.code === 0 && created?.data?.uuid && created?.data?.invite_link) {
    return {
      source: 'created',
      chatId: created.data.uuid,
      inviteLink: created.data.invite_link,
    };
  }

  const canReuse =
    created?.code === 400 &&
    String(created?.message || '').includes('创建群组数量已达上限');
  if (!canReuse) {
    throw new Error(`Create QR group failed: ${JSON.stringify(created)}`);
  }

  const reusable = await findReusableQrGroup(peer.token);
  if (!reusable) {
    throw new Error(`Create QR group failed and no reusable group found: ${JSON.stringify(created)}`);
  }
  return {
    source: 'reused',
    chatId: reusable.chatId,
    inviteLink: reusable.inviteLink,
    createFallbackReason: created.message,
  };
}

async function findReusableQrGroup(token) {
  const json = await getJson('/api/v1/chat/list?page=1&page_size=100', token);
  const list = Array.isArray(json?.data?.list) ? json.data.list : [];
  const groups = list
    .filter((item) => item?.type === 2)
    .sort((a, b) => {
      const aName = String(a?.name || '');
      const bName = String(b?.name || '');
      const aScore = aName.startsWith('QR Smoke') ? 1 : 0;
      const bScore = bName.startsWith('QR Smoke') ? 1 : 0;
      return bScore - aScore;
    });

  for (const group of groups.slice(0, 20)) {
    const chatId = group.chat_id || group.uuid;
    if (!chatId) continue;
    const detail = await getJson(`/api/v1/chat/${encodeURIComponent(chatId)}`, token);
    const inviteLink = detail?.data?.invite_link;
    const uuid = detail?.data?.uuid || chatId;
    if (detail?.code === 0 && inviteLink && uuid) {
      return { chatId: uuid, inviteLink };
    }
  }
  return null;
}

async function smokeLoginQr(scanner) {
  const created = await postJson('/api/v1/auth/qr-login/create', {
    device_id: `web-qr-login-${Date.now()}`,
    device_type: 'web',
    device_name: 'Flutter Web QR Login Smoke',
  });
  if (created?.code !== 0 || !created?.data?.ticket || !created?.data?.secret) {
    throw new Error(`Create QR login failed: ${JSON.stringify(created)}`);
  }

  const raw = created.data.qr_text || buildLoginQrPayload(created.data.ticket);
  const payload = assertPayload(raw, 'login');
  if (payload.id !== created.data.ticket) {
    throw new Error(
      `QR login payload ticket mismatch: ${JSON.stringify({ payload, created: created.data })}`,
    );
  }

  const beforeConfirm = await getJson(
    `/api/v1/auth/qr-login/status/${encodeURIComponent(created.data.ticket)}`,
    '',
  );
  if (beforeConfirm?.code !== 0 || beforeConfirm?.data?.status !== 'pending') {
    throw new Error(`QR login initial status failed: ${JSON.stringify(beforeConfirm)}`);
  }

  const confirmed = await postJson(
    `/api/v1/auth/qr-login/confirm/${encodeURIComponent(created.data.ticket)}`,
    {},
    scanner.token,
  );
  if (confirmed?.code !== 0 || confirmed?.data?.status !== 'confirmed') {
    throw new Error(`QR login confirm failed: ${JSON.stringify(confirmed)}`);
  }

  const afterConfirm = await getJson(
    `/api/v1/auth/qr-login/status/${encodeURIComponent(created.data.ticket)}?secret=${encodeURIComponent(created.data.secret)}`,
    '',
  );
  if (
    afterConfirm?.code !== 0 ||
    afterConfirm?.data?.status !== 'confirmed' ||
    !afterConfirm?.data?.token
  ) {
    throw new Error(`QR login confirmed status failed: ${JSON.stringify(afterConfirm)}`);
  }

  const tokenMe = await getJson('/api/v1/user/me', afterConfirm.data.token);
  if (tokenMe?.code !== 0 || tokenMe?.data?.uuid !== scanner.user.uuid) {
    throw new Error(`QR login token validation failed: ${JSON.stringify(tokenMe)}`);
  }

  return {
    raw,
    parsed: payload,
    ticket: created.data.ticket,
    initialStatus: beforeConfirm.data.status,
    confirmedStatus: afterConfirm.data.status,
    tokenUserUuid: tokenMe.data.uuid,
  };
}

function assertPayload(raw, expectedType) {
  const payload = parseOneChatQrPayload(raw);
  if (!payload || payload.type !== expectedType || !payload.id) {
    throw new Error(`Invalid QR payload: ${JSON.stringify({ raw, payload, expectedType })}`);
  }
  return payload;
}

async function postJson(path, data, token = '') {
  const response = await fetch(`${apiBase}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(data),
  });
  return response.json();
}

async function getJson(path, token = '') {
  const response = await fetch(`${apiBase}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return response.json();
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
