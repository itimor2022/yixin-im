// 文件用途：验证 hot_update_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestCompareVersion(t *testing.T) {
	if got := compareVersion("1.2.0+10", "1.2.0+9"); got != 1 {
		t.Fatalf("expected 1, got %d", got)
	}
	if got := compareVersion("1.0", "1.0.0"); got != 0 {
		t.Fatalf("expected 0, got %d", got)
	}
	if got := compareVersion("1.0.0", "1.0.1"); got != -1 {
		t.Fatalf("expected -1, got %d", got)
	}
}

func TestIsInRolloutDeterministic(t *testing.T) {
	seed := buildRolloutSeed("patch-001", "user-abc", "", "")

	hit1, bucket1 := isInRollout(seed, 30)
	hit2, bucket2 := isInRollout(seed, 30)
	if hit1 != hit2 || bucket1 != bucket2 {
		t.Fatalf("rollout should be deterministic: (%v,%d) vs(%v,%d)", hit1, bucket1, hit2, bucket2)
	}
	if ok, _ := isInRollout(seed, 0); ok {
		t.Fatalf("0%% rollout should never hit")
	}
	if ok, _ := isInRollout(seed, 100); !ok {
		t.Fatalf("100%% rollout should always hit")
	}
}

func TestPatchEligibility(t *testing.T) {
	now := time.Now()
	start := now.Add(-time.Hour)
	end := now.Add(time.Hour)
	patch := models.HotUpdatePatch{
		MinAppVersion:     "1.0.0",
		MaxAppVersion:     "2.0.0",
		MinBuildNumber:    10,
		MaxBuildNumber:    20,
		RolloutPercentage: 30,
		StartAt:           &start,
		EndAt:             &end,
	}
	if !isPatchEligibleForClient(patch, "1.5.0", 15, now) {
		t.Fatalf("expected patch eligible")
	}
	if isPatchEligibleForClient(patch, "2.1.0", 15, now) {
		t.Fatalf("expected version overflow to be ineligible")
	}
	if isPatchEligibleForClient(patch, "1.5.0", 9, now) {
		t.Fatalf("expected low build to be ineligible")
	}
	past := now.Add(2 * time.Hour)
	if isPatchEligibleForClient(patch, "1.5.0", 15, past) {
		t.Fatalf("expected expired patch to be ineligible")
	}
	patch.TargetAppVersion = "1.5.0+15"
	if isPatchEligibleForClient(patch, "1.5.0", 15, now) {
		t.Fatalf("expected target version reached to be ineligible")
	}
	if !isPatchEligibleForClient(patch, "1.5.0", 14, now) {
		t.Fatalf("expected lower build than target version to stay eligible")
	}
}

func TestNormalizeHotUpdateReportStatus(t *testing.T) {
	cases := []string{
		models.HotUpdatePatchReportStatusCheckHit,
		models.HotUpdatePatchReportStatusDeferred,
		models.HotUpdatePatchReportStatusApplySuccess,
		models.HotUpdatePatchReportStatusInstallStarted,
		models.HotUpdatePatchReportStatusInstallConfirmed,
		models.HotUpdatePatchReportStatusApplyFailed,
		models.HotUpdatePatchReportStatusSDKNotIntegrated,
		models.HotUpdatePatchReportStatusSDKNotAvailable,
	}
	for _, item := range cases {
		if got := normalizeHotUpdateReportStatus(item); got != item {
			t.Fatalf("expected %s, got %s", item, got)
		}
	}
	if got := normalizeHotUpdateReportStatus("unknown_status"); got != "" {
		t.Fatalf("expected empty status for invalid input, got %s", got)
	}
}

func TestParseHotUpdateBoolFlag(t *testing.T) {
	trueCases := []string{"1", "true", "TRUE", "yes", "Y", "on"}
	for _, item := range trueCases {
		if !parseHotUpdateBoolFlag(item) {
			t.Fatalf("expected %q to parse as true", item)
		}
	}
	falseCases := []string{"", "0", "false", "off", "no", "random"}
	for _, item := range falseCases {
		if parseHotUpdateBoolFlag(item) {
			t.Fatalf("expected %q to parse as false", item)
		}
	}
}

func TestValidateHotUpdatePatchURL(t *testing.T) {
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformAndroid, "https://cdn.example.com/app.apk"); err != nil {
		t.Fatalf("expected android https apk url valid, got %v", err)
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformAndroid, "http://cdn.example.com/app.apk"); err == nil {
		t.Fatalf("expected android http url invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformAndroid, "https://cdn.example.com/app.zip"); err == nil {
		t.Fatalf("expected android non-apk url invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "https://cdn.example.com/manifest.plist"); err != nil {
		t.Fatalf("expected ios plist url valid, got %v", err)
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "itms-services://?action=download-manifest&url=https://cdn.example.com/manifest.plist"); err != nil {
		t.Fatalf("expected ios itms-services url valid, got %v", err)
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "https://cdn.example.com/download.html"); err == nil {
		t.Fatalf("expected ios non-plist url invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "itms-services://?action=download-manifest"); err == nil {
		t.Fatalf("expected ios itms-services url without embedded plist invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "itms-services://?action=download-manifest&url=ftp://cdn.example.com/manifest.plist"); err == nil {
		t.Fatalf("expected ios itms-services url with non-http embedded plist invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "itms-services://?action=download-manifest&url=http://cdn.example.com/manifest.plist"); err == nil {
		t.Fatalf("expected ios itms-services url with http embedded plist invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformIOS, "itms-services://?action=download-manifest&url=https://cdn.example.com/download.html"); err == nil {
		t.Fatalf("expected ios itms-services url without plist suffix invalid")
	}
	if err := validateHotUpdatePatchURL(models.HotUpdatePatchPlatformAndroid, "itms-services://?action=download-manifest&url=https://cdn.example.com/manifest.plist"); err == nil {
		t.Fatalf("expected android itms-services url invalid")
	}
}

func TestValidateHotUpdatePatchHash(t *testing.T) {
	validCases := []string{
		"",
		"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}
	for _, item := range validCases {
		if err := validateHotUpdatePatchHash(item); err != nil {
			t.Fatalf("expected hash valid for %q, got %v", item, err)
		}
	}
	if err := validateHotUpdatePatchHash("sha256:abc"); err == nil {
		t.Fatalf("expected short hash invalid")
	}
	if err := validateHotUpdatePatchHash("md5:0123456789abcdef0123456789abcdef"); err == nil {
		t.Fatalf("expected md5 hash invalid")
	}
}

func TestValidateSelfHostedHotUpdatePatch(t *testing.T) {
	validHash := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	if err := validateSelfHostedHotUpdatePatch(models.HotUpdatePatchPlatformAndroid, "https://cdn.example.com/app.apk", validHash); err != nil {
		t.Fatalf("expected self_hosted android patch valid, got %v", err)
	}
	if err := validateSelfHostedHotUpdatePatch(models.HotUpdatePatchPlatformAndroid, "https://cdn.example.com/app.apk", ""); err == nil {
		t.Fatalf("expected missing self_hosted hash invalid")
	}
	if err := validateSelfHostedHotUpdatePatch(models.HotUpdatePatchPlatformAndroid, "https://cdn.example.com/app.apk", "md5:0123456789abcdef0123456789abcdef"); err == nil {
		t.Fatalf("expected non-sha256 self_hosted hash invalid")
	}
}

func TestNormalizeHotUpdateDeliveryMode(t *testing.T) {
	if got := normalizeHotUpdateDeliveryMode(""); got != models.HotUpdatePatchDeliveryModeSelfHosted {
		t.Fatalf("expected empty delivery mode to default to self_hosted, got %s", got)
	}
	if got := normalizeHotUpdateDeliveryMode("shorebird"); got != models.HotUpdatePatchDeliveryModeShorebird {
		t.Fatalf("expected shorebird delivery mode, got %s", got)
	}
	if got := normalizeHotUpdateDeliveryMode("invalid"); got != "" {
		t.Fatalf("expected invalid delivery mode to normalize to empty, got %s", got)
	}
}

func TestNormalizeHotUpdatePatchStatus(t *testing.T) {
	cases := []string{
		models.HotUpdatePatchStatusDraft,
		models.HotUpdatePatchStatusPublished,
		models.HotUpdatePatchStatusPaused,
		models.HotUpdatePatchStatusRolledBack,
	}
	for _, item := range cases {
		if got := normalizeHotUpdatePatchStatus(item); got != item {
			t.Fatalf("expected %s, got %s", item, got)
		}
	}
	if got := normalizeHotUpdatePatchStatus("invalid"); got != "" {
		t.Fatalf("expected invalid patch status to normalize to empty, got %s", got)
	}
}

func TestNormalizeHotUpdatePatchReportRecord(t *testing.T) {
	report := models.HotUpdatePatchReport{}
	normalizeHotUpdatePatchReportRecord(&report)
	if report.DeliveryMode != models.HotUpdatePatchDeliveryModeSelfHosted {
		t.Fatalf("expected report delivery mode to default to self_hosted, got %s", report.DeliveryMode)
	}
}

func TestBuildPatchFromRequestByDeliveryMode(t *testing.T) {
	selfHostedReq := hotUpdatePatchUpsertRequest{
		Name:         "Self Hosted",
		Platform:     models.HotUpdatePatchPlatformAndroid,
		DeliveryMode: models.HotUpdatePatchDeliveryModeSelfHosted,
		PatchVersion: "2026.05.10.1",
		PatchURL:     "https://cdn.example.com/app.apk",
		PatchHash:    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}
	values, err := buildPatchFromRequest(selfHostedReq, nil, 1, true)
	if err != nil {
		t.Fatalf("expected self_hosted request valid, got %v", err)
	}
	if readString(values, "delivery_mode") != models.HotUpdatePatchDeliveryModeSelfHosted {
		t.Fatalf("expected self_hosted delivery mode in payload")
	}
	if readString(values, "patch_url") == "" {
		t.Fatalf("expected self_hosted patch_url to be preserved")
	}
	shorebirdReq := hotUpdatePatchUpsertRequest{
		Name:         "Shorebird Patch",
		Platform:     models.HotUpdatePatchPlatformAndroid,
		DeliveryMode: models.HotUpdatePatchDeliveryModeShorebird,
		PatchVersion: "2026.05.10.2",
		PatchURL:     "",
		PatchHash:    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}
	values, err = buildPatchFromRequest(shorebirdReq, nil, 1, true)
	if err != nil {
		t.Fatalf("expected shorebird request valid, got %v", err)
	}
	if readString(values, "delivery_mode") != models.HotUpdatePatchDeliveryModeShorebird {
		t.Fatalf("expected shorebird delivery mode in payload")
	}
	if readString(values, "patch_url") != "" {
		t.Fatalf("expected shorebird patch_url to be cleared")
	}
	if readString(values, "patch_hash") != "" {
		t.Fatalf("expected shorebird patch_hash to be cleared")
	}
	invalidSelfHostedReq := hotUpdatePatchUpsertRequest{
		Name:         "Invalid Self Hosted",
		Platform:     models.HotUpdatePatchPlatformAll,
		DeliveryMode: models.HotUpdatePatchDeliveryModeSelfHosted,
		PatchVersion: "2026.05.10.3",
		PatchURL:     "https://cdn.example.com/app.apk",
	}
	if _, err := buildPatchFromRequest(invalidSelfHostedReq, nil, 1, true); err == nil {
		t.Fatalf("expected self_hosted all-platform request invalid")
	}
}
