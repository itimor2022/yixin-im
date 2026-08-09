package services

import (
	"strings"
	"testing"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

func newRelationshipDryRunDB(t *testing.T) *gorm.DB {
	t.Helper()

	db, err := gorm.Open(
		mysql.New(mysql.Config{
			DSN:                       "test:test@tcp(127.0.0.1:3306)/test",
			SkipInitializeWithVersion: true,
		}),
		&gorm.Config{
			DryRun:                 true,
			DisableAutomaticPing:   true,
			SkipDefaultTransaction: true,
		},
	)
	if err != nil {
		t.Fatalf("open dry-run database: %v", err)
	}
	return db
}

func TestActiveCommonGroupsQueryFiltersLifecycleAndSupportsGroupsAndChannels(t *testing.T) {
	db := newRelationshipDryRunDB(t)
	var rows []struct {
		ID uint64
	}

	statement := activeCommonGroupsQuery(db, 22, []uint64{101, 102}).
		Find(&rows).
		Statement
	sql := statement.SQL.String()

	for _, fragment := range []string{
		"INNER JOIN chat_members ON chats.id = chat_members.chat_id",
		"chat_members.user_id = ?",
		"chats.id IN (?,?)",
		"chats.type IN (?,?)",
		"chats.status = ?",
	} {
		if !strings.Contains(sql, fragment) {
			t.Fatalf("query is missing %q: %s", fragment, sql)
		}
	}

	wantVars := []interface{}{uint64(22), uint64(101), uint64(102), 2, 3, 0}
	if len(statement.Vars) != len(wantVars) {
		t.Fatalf("unexpected bind variables: %#v", statement.Vars)
	}
	for i, want := range wantVars {
		if statement.Vars[i] != want {
			t.Fatalf("bind variable %d = %#v, want %#v", i, statement.Vars[i], want)
		}
	}
}

func TestActiveCommonGroupsQueryUsesSameFilterForListAndCount(t *testing.T) {
	db := newRelationshipDryRunDB(t)

	var rows []struct {
		ID uint64
	}
	listStatement := activeCommonGroupsQuery(db, 22, []uint64{101}).
		Find(&rows).
		Statement

	var count int64
	countStatement := activeCommonGroupsQuery(db, 22, []uint64{101}).
		Count(&count).
		Statement

	for name, statement := range map[string]*gorm.Statement{
		"list":  listStatement,
		"count": countStatement,
	} {
		sql := statement.SQL.String()
		if !strings.Contains(sql, "chats.status = ?") {
			t.Fatalf("%s query does not filter dissolved chats: %s", name, sql)
		}
		if got := statement.Vars[len(statement.Vars)-1]; got != 0 {
			t.Fatalf("%s query lifecycle status = %#v, want normal status 0", name, got)
		}
	}
}
