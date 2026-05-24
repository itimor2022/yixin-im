import asyncio, aiohttp, uuid, time, statistics

BASE_URL = "https://web.unf58.icu"
TOTAL_USERS = 5000
CONCURRENT_MSG = 300
MSG_ROUNDS = 10
REG_CONCURRENCY = 10

async def register_or_login(session, i):
    # 先尝试注册
    try:
        async with session.post(f"{BASE_URL}/api/v1/auth/register", json={
            "username": f"large_user_{i:05d}",
            "password": "Test123456",
            "nickname": f"大群用户{i}",
            "device_id": f"large-device-{i:05d}",
            "device_type": "android"
        }, timeout=aiohttp.ClientTimeout(total=20)) as r:
            data = await r.json()
            if data.get("code") == 0:
                return data["data"]["token"], data["data"]["uuid"]
    except Exception:
        pass

    # 注册失败则登录
    try:
        async with session.post(f"{BASE_URL}/api/v1/auth/login", json={
            "username": f"large_user_{i:05d}",
            "password": "Test123456",
            "device_id": f"large-device-{i:05d}",
            "device_type": "android"
        }, timeout=aiohttp.ClientTimeout(total=20)) as r:
            data = await r.json()
            if data.get("code") == 0:
                return data["data"]["token"], data["data"]["user"]["uuid"]
    except Exception as e:
        print(f"  ❌ 用户{i}失败: {type(e).__name__}: {e}")
    return None, None

async def main():
    connector = aiohttp.TCPConnector(limit=500, ssl=False)
    async with aiohttp.ClientSession(connector=connector) as session:

        # 1. 批量注册/登录
        print(f"📝 批量注册/登录 {TOTAL_USERS} 个用户（并发={REG_CONCURRENCY}）...")
        sem = asyncio.Semaphore(REG_CONCURRENCY)
        async def safe_reg(i):
            async with sem:
                return await register_or_login(session, i)
        results = await asyncio.gather(*[safe_reg(i) for i in range(TOTAL_USERS)])
        tokens = [t for t, u in results if t]
        uuids  = [u for t, u in results if u]
        print(f"  ✅ 可用用户: {len(tokens)}")
        if len(tokens) < 10:
            print("❌ 用户数不足，退出"); return

        # 2. 创建群聊
        print(f"\n🏗️  创建大群（加入前500人）...")
        chat_id = None
        try:
            async with session.post(f"{BASE_URL}/api/v1/chat/create",
                json={"type": 2, "name": f"压测大群_{len(uuids)}人", "member_ids": uuids[1:501]},
                headers={"Authorization": f"Bearer {tokens[0]}"},
                timeout=aiohttp.ClientTimeout(total=30)) as r:
                data = await r.json()
                if data.get("code") == 0:
                    chat_id = data["data"]["uuid"]
                    print(f"  ✅ 群创建成功: {chat_id}")
                else:
                    print(f"  ❌ 创建失败: {data}"); return
        except Exception as e:
            print(f"  ❌ 异常: {e}"); return

        # 3. 分批加入剩余成员
        remaining = uuids[501:]
        batch_size = 500
        for bi, start in enumerate(range(0, len(remaining), batch_size)):
            batch = remaining[start:start+batch_size]
            try:
                async with session.post(f"{BASE_URL}/api/v1/chat/{chat_id}/members",
                    json={"user_ids": batch},
                    headers={"Authorization": f"Bearer {tokens[0]}"},
                    timeout=aiohttp.ClientTimeout(total=30)) as r:
                    data = await r.json()
                    status = "✅" if data.get("code") == 0 else "❌"
                    print(f"  {status} 批次{bi+2}: 加入{len(batch)}人 {data.get('message','')}")
            except Exception as e:
                print(f"  ❌ 批次{bi+2}异常: {e}")
            await asyncio.sleep(0.5)

        # 4. 并发压测
        print(f"\n🚀 压测: {CONCURRENT_MSG} 并发，每轮各发1条，共 {MSG_ROUNDS} 轮")
        all_latencies = []
        total_ok, total_fail = 0, 0
	async def send_msg(token, round_i, user_i):
            t0 = time.time()
            try:
                async with session.post(f"{BASE_URL}/api/v1/message/send",
                    json={"chat_id": chat_id, "type": 1,
                          "msg_id": str(uuid.uuid4()),
                          "content": {"text": f"大群压测 r={round_i} u={user_i}"}},
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=aiohttp.ClientTimeout(total=10)) as r:
                    data = await r.json()
                    elapsed = (time.time() - t0) * 1000
                    ok = data.get("code") == 0
                    return ok, elapsed, data.get("code"), data.get("message","")
            except Exception as e:
                return False, (time.time()-t0)*1000, -1, str(e)

        for round_i in range(1, MSG_ROUNDS+1):
            user_tokens = tokens[:CONCURRENT_MSG]
            results = await asyncio.gather(*[send_msg(t, round_i, i) for i, t in enumerate(user_tokens)])
            ok = sum(1 for r in results if r[0])
            fail = len(results) - ok
            lats = [r[1] for r in results]
            all_latencies.extend([r[1] for r in results if r[0]])
            total_ok += ok; total_fail += fail
            print(f"  Round {round_i:2d}: ok={ok}/{len(results)}  avg={statistics.mean(lats):.0f}ms  min={min(lats):.0f}ms  max={max(lats):.0f}ms")
            if fail:
                codes = set(r[2] for r in results if not r[0])
                print(f"           ❌ codes={codes} 示例: {next((r[3] for r in results if not r[0]),'')}")
            await asyncio.sleep(0.3)

        print(f"\n{'='*50}")
        print(f"📊 压测结果")
        print(f"  群成员数:  {len(uuids)}")
        print(f"  总消息数:  {total_ok+total_fail}  成功: {total_ok}  失败: {total_fail}")
        print(f"  成功率:    {total_ok/(total_ok+total_fail)*100:.1f}%")
        if all_latencies:
            all_latencies.sort()
            n = len(all_latencies)
            print(f"  P50延迟:   {all_latencies[int(n*0.5)]:.0f}ms")
            print(f"  P95延迟:   {all_latencies[int(n*0.95)]:.0f}ms")
            print(f"  P99延迟:   {all_latencies[min(int(n*0.99),n-1)]:.0f}ms")

asyncio.run(main())
