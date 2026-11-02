// Package migrations embeds the SQL shipped with the application image.
package migrations

import "embed"

// Files contains versioned forward migrations.
//
//go:embed *.up.sql
var Files embed.FS
