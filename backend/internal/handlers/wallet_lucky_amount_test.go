// 文件用途：验证 wallet_lucky_amount_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import "testing"

func TestSecureLuckyAmountCentsRejectsInvalidState(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name           string
		remainingCents int64
		count          int
	}{
		{name: "zero count", remainingCents: 100, count: 0},
		{name: "negative count", remainingCents: 100, count: -1},
		{name: "not enough for minimum claims", remainingCents: 2, count: 3},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if _, err := secureLuckyAmountCents(tt.remainingCents, tt.count); err == nil {
				t.Fatal("secureLuckyAmountCents() error = nil, want error")
			}
		})
	}
}

func TestSecureLuckyAmountCentsReturnsAllForLastClaim(t *testing.T) {
	t.Parallel()

	amount, err := secureLuckyAmountCents(12345, 1)
	if err != nil {
		t.Fatalf("secureLuckyAmountCents() error = %v", err)
	}
	if amount != 12345 {
		t.Fatalf("secureLuckyAmountCents() = %d, want 12345", amount)
	}
}

func TestSecureLuckyAmountCentsPreservesTotalAndMinimum(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		totalCents int64
		count      int
	}{
		{name: "minimum one cent each", totalCents: 3, count: 3},
		{name: "small packet", totalCents: 100, count: 10},
		{name: "medium packet", totalCents: 10000, count: 100},
		{name: "uneven large packet", totalCents: 999999, count: 257},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for round := 0; round < 50; round++ {
				remaining := tt.totalCents
				remainingCount := tt.count
				var claimed int64

				for remainingCount > 0 {
					before := remaining
					amount, err := secureLuckyAmountCents(remaining, remainingCount)
					if err != nil {
						t.Fatalf("round %d, remaining=%d, count=%d: %v", round, remaining, remainingCount, err)
					}
					if amount < 1 {
						t.Fatalf("round %d: amount = %d, want at least 1 cent", round, amount)
					}
					if remainingCount > 1 {
						maxByDoubleMean := before * 2 / int64(remainingCount)
						maxAvailable := before - int64(remainingCount-1)
						if maxByDoubleMean > maxAvailable {
							maxByDoubleMean = maxAvailable
						}
						if amount > maxByDoubleMean {
							t.Fatalf("round %d: amount = %d, want <= %d", round, amount, maxByDoubleMean)
						}
					}

					remaining -= amount
					claimed += amount
					remainingCount--
					if remaining < int64(remainingCount) {
						t.Fatalf("round %d: remaining = %d cannot fund %d minimum claims", round, remaining, remainingCount)
					}
				}
				if remaining != 0 {
					t.Fatalf("round %d: remaining = %d, want 0", round, remaining)
				}
				if claimed != tt.totalCents {
					t.Fatalf("round %d: claimed = %d, want %d", round, claimed, tt.totalCents)
				}
			}
		})
	}
}
