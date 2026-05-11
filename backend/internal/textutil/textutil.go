package textutil

// TruncateRunes returns s limited to max runes. It avoids cutting UTF-8
// sequences in the middle, which can corrupt Chinese text or emoji.
func TruncateRunes(s string, max int) string {
	if max <= 0 {
		return ""
	}
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max])
}

// TruncateRunesWithSuffix truncates s to max runes and appends suffix only
// when truncation actually happened.
func TruncateRunesWithSuffix(s string, max int, suffix string) string {
	if max <= 0 {
		return ""
	}
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max]) + suffix
}
