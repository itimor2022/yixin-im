#!/usr/bin/env node

import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const apiBase = (process.env.GENERIC_IM_SERVER_URL || 'http://127.0.0.1:8080').replace(/\/+$/, '');
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'smoke_alice';
const peerUsername = process.env.GENERIC_IM_SMOKE_PEER_USERNAME || 'smoke_bob';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || 'Smoke123';
const artifactPath = resolve(
  process.env.GENERIC_IM_SMOKE_INTEGRITY_ARTIFACT ||
    'artifacts/delivery-acceptance-20260728/flutter-web-s3-message-integrity-20260728/message-integrity.json',
);

const fixtures = {
  private: {
    chatId: 'a0420996-9c84-4a1c-b9a0-402fd8ba2992',
    messages: [
      { msgId: '02279635-91f4-4bf2-9c71-8829ea042b7c', seq: 2176, type: 2, revoked: false },
      { msgId: 'fd202be9-e165-4597-ad9a-d71a4a226eb3', seq: 2177, type: 3, revoked: false },
    ],
  },
  group: {
    chatId: '99ad8f56-bf01-44a7-922f-756d7cb99bec',
    messages: [
      { msgId: '8cb3975c-04d9-4222-a5a9-6ae17426a55c', seq: 57, type: 2, revoked: false },
      { msgId: '3bfc4a45-07ff-42f2-bb89-318a85e43779', seq: 58, type: 3, revoked: true },
      { msgId: '89fa2cf8-2472-4f99-b68a-cce09855e8a8', seq: 59, type: 2, revoked: false },
      { msgId: 'b45a50cf-465a-42c4-ab99-b452da735814', seq: 60, type: 3, revoked: false },
    ],
  },
};

async function request(path, { method = 'GET', token, data } = {}) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      accept: 'application/json',
      ...(data ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: data ? JSON.stringify(data) : undefined,
  });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!response.ok) {
    throw new Error(`${method} ${path} ${response.status}: ${text.slice(0, 500)}`);
  }
  return body;
}

async function login(name) {
  const body = await request('/api/v1/auth/login', {
    method: 'POST',
    data: {
      username: name,
      password,
      device_id: `integrity-${name}-${Date.now()}`,
      device_type: 'web',
      device_name: 'S3 Message Integrity Acceptance',
    },
  });
  if (body?.code !== 0 || !body?.data?.token) {
    throw new Error(`Login failed for ${name}: ${JSON.stringify(body)}`);
  }
  return body.data.token;
}

async function listMessages(token, chatId) {
  const body = await request(
    `/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=100`,
    { token },
  );
  const messages = Array.isArray(body?.data) ? body.data : body?.data?.list;
  if (!Array.isArray(messages)) {
    throw new Error(`Unexpected message list response for ${chatId}: ${JSON.stringify(body)}`);
  }
  return messages;
}

function evidence(message) {
  return {
    msg_id: String(message.msg_id),
    seq: Number(message.seq),
    type: Number(message.type),
    is_revoked: message.is_revoked === true,
    media_id: message.content?.media?.media_id || null,
    thumbnail_media_id: message.content?.media?.thumbnail_media_id || null,
    mime_type: message.content?.media?.mime_type || null,
  };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function verifyChat(chat, senderMessages, receiverMessages) {
  const senderById = new Map(senderMessages.map((message) => [String(message.msg_id), message]));
  const receiverById = new Map(receiverMessages.map((message) => [String(message.msg_id), message]));
  const selected = chat.messages.map((expected) => {
    const sender = senderById.get(expected.msgId);
    const receiver = receiverById.get(expected.msgId);
    assert(sender, `Sender missing ${expected.msgId} in ${chat.chatId}`);
    assert(receiver, `Receiver missing ${expected.msgId} in ${chat.chatId}`);
    const senderEvidence = evidence(sender);
    const receiverEvidence = evidence(receiver);
    assert(senderEvidence.seq === expected.seq, `Sender seq mismatch for ${expected.msgId}`);
    assert(receiverEvidence.seq === expected.seq, `Receiver seq mismatch for ${expected.msgId}`);
    assert(senderEvidence.type === expected.type, `Sender type mismatch for ${expected.msgId}`);
    assert(receiverEvidence.type === expected.type, `Receiver type mismatch for ${expected.msgId}`);
    assert(senderEvidence.is_revoked === expected.revoked, `Sender revoke mismatch for ${expected.msgId}`);
    assert(receiverEvidence.is_revoked === expected.revoked, `Receiver revoke mismatch for ${expected.msgId}`);
    assert(
      JSON.stringify(senderEvidence) === JSON.stringify(receiverEvidence),
      `Sender/receiver fields differ for ${expected.msgId}`,
    );
    assert(senderEvidence.media_id, `Missing media_id for ${expected.msgId}`);
    if (expected.type === 3) {
      assert(senderEvidence.thumbnail_media_id, `Missing thumbnail_media_id for ${expected.msgId}`);
    }
    return { expected, sender: senderEvidence, receiver: receiverEvidence };
  });

  const seqs = selected.map((item) => item.sender.seq);
  for (let index = 1; index < seqs.length; index += 1) {
    assert(seqs[index] === seqs[index - 1] + 1, `Non-contiguous selected seqs in ${chat.chatId}`);
  }
  return {
    chatId: chat.chatId,
    selected,
    selectedSeqs: seqs,
    seqContinuous: true,
    senderMessageCount: senderMessages.length,
    receiverMessageCount: receiverMessages.length,
  };
}

async function main() {
  const senderToken = await login(username);
  const receiverToken = await login(peerUsername);
  const result = {
    ok: false,
    apiBase,
    accounts: { sender: username, receiver: peerUsername },
    checks: {},
  };

  for (const [name, chat] of Object.entries(fixtures)) {
    const [senderMessages, receiverMessages] = await Promise.all([
      listMessages(senderToken, chat.chatId),
      listMessages(receiverToken, chat.chatId),
    ]);
    result.checks[name] = verifyChat(chat, senderMessages, receiverMessages);
  }

  result.ok = true;
  result.completedAt = new Date().toISOString();
  mkdirSync(resolve(artifactPath, '..'), { recursive: true });
  writeFileSync(artifactPath, `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify({ ...result, artifactPath }, null, 2));
}

main().catch((error) => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
