// Package indegostations provides details for the Indego Stations applet.
package pooltemp

import (
	_ "embed"

	"tidbyt.dev/community/apps/manifest"
)

//go:embed pool_temp.star
var source []byte

// New creates a new instance of the Indego Stations applet.
func New() manifest.Manifest {
	return manifest.Manifest{
		ID:          "pool-temp",
		Name:        "Pool/Spa Temp",
		Author:      "smith288",
		Summary:     "Get spa and pool temps using a Shelly Uni",
		Desc:        "Provide the status URL of the Shelly Uni and it will grab the 0 and 1 temperatures.",
		FileName:    "pool_temp.star",
		PackageName: "pooltemp",
		Source:      source,
	}
}
