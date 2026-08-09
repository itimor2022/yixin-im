// 文件用途：实现 backend 目录中的 shard_lock.go 模块。
// 核心逻辑：围绕本文件的类型和函数完成输入处理、状态转换或辅助计算。

package shard

import (
	"hash/fnv"
	"sync"
)

// ShardedLock 分片锁 - 用于高并发场景下的细粒度锁控制
// 通过将锁分散到多个分片，减少锁竞争，提高并发性能
type ShardedLock struct {
	shards    []sync.RWMutex
	shardMask uint32
}

// NewShardedLock 创建分片锁
// shardCount 建议为2的幂次方，如 32, 64, 128, 256
func NewShardedLock(shardCount int) *ShardedLock {
	// 确保是2的幂次方
	if shardCount <= 0 {
		shardCount = 64
	}

	// 向上取整到2的幂次方
	n := uint32(1)
	for n < uint32(shardCount) {
		n *= 2
	}
	return &ShardedLock{
		shards:    make([]sync.RWMutex, n),
		shardMask: n - 1,
	}
}

// getShard 根据key获取

func (sl *ShardedLock) getShard(key string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(key))
	return h.Sum32() & sl.shardMask
}

// Lock 获取

func (sl *ShardedLock) Lock(key string) {
	sl.shards[sl.getShard(key)].Lock()
}

// Unlock 释放写锁
func (sl *ShardedLock) Unlock(key string) {
	sl.shards[sl.getShard(key)].Unlock()
}

// RLock 获取读锁
func (sl *ShardedLock) RLock(key string) {
	sl.shards[sl.getShard(key)].RLock()
}

// RUnlock 释放读锁
func (sl *ShardedLock) RUnlock(key string) {
	sl.shards[sl.getShard(key)].RUnlock()
}

// ShardedMap 分片Map - 用于高并发读写的Map
type ShardedMap[V any] struct {
	shards    []mapShard[V]
	shardMask uint32
}

type mapShard[V any] struct {
	sync.RWMutex
	items map[string]V
}

// NewShardedMap 创建分片Map
func NewShardedMap[V any](shardCount int) *ShardedMap[V] {
	if shardCount <= 0 {
		shardCount = 64
	}
	n := uint32(1)
	for n < uint32(shardCount) {
		n *= 2
	}
	shards := make([]mapShard[V], n)
	for i := range shards {
		shards[i].items = make(map[string]V)
	}
	return &ShardedMap[V]{
		shards:    shards,
		shardMask: n - 1,
	}
}

func (sm *ShardedMap[V]) getShard(key string) *mapShard[V] {
	h := fnv.New32a()
	h.Write([]byte(key))
	return &sm.shards[h.Sum32()&sm.shardMask]
}

// Set 设置值
func (sm *ShardedMap[V]) Set(key string, value V) {
	shard := sm.getShard(key)
	shard.Lock()
	shard.items[key] = value
	shard.Unlock()
}

// Get 获取值
func (sm *ShardedMap[V]) Get(key string) (V, bool) {
	shard := sm.getShard(key)
	shard.RLock()
	value, ok := shard.items[key]
	shard.RUnlock()
	return value, ok
}

// Delete 删除值
func (sm *ShardedMap[V]) Delete(key string) {
	shard := sm.getShard(key)
	shard.Lock()
	delete(shard.items, key)
	shard.Unlock()
}

// Has 检查key是否存在
func (sm *ShardedMap[V]) Has(key string) bool {
	shard := sm.getShard(key)
	shard.RLock()
	_, ok := shard.items[key]
	shard.RUnlock()
	return ok
}

// Count 获取

func (sm *ShardedMap[V]) Count() int {
	count := 0
	for i := range sm.shards {
		sm.shards[i].RLock()
		count += len(sm.shards[i].items)
		sm.shards[i].RUnlock()
	}
	return count
}

// Keys 获取

func (sm *ShardedMap[V]) Keys() []string {
	keys := make([]string, 0)
	for i := range sm.shards {
		sm.shards[i].RLock()
		for k := range sm.shards[i].items {
			keys = append(keys, k)
		}
		sm.shards[i].RUnlock()
	}
	return keys
}

// Range

func (sm *ShardedMap[V]) Range(f func(key string, value V) bool) {
	for i := range sm.shards {
		sm.shards[i].RLock()
		for k, v := range sm.shards[i].items {
			if !f(k, v) {
				sm.shards[i].RUnlock()
				return
			}
		}
		sm.shards[i].RUnlock()
	}
}

// Clear 清空
func (sm *ShardedMap[V]) Clear() {
	for i := range sm.shards {
		sm.shards[i].Lock()
		sm.shards[i].items = make(map[string]V)
		sm.shards[i].Unlock()
	}
}
