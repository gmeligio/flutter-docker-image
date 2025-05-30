package windows

import (
	"testing"
	"time"

	"github.com/ory/dockertest/v3"
	"github.com/stretchr/testify/require"
)

func TestWithFlutter(t *testing.T) {
	pool, err := dockertest.NewPool("")
	require.NoError(t, err)

	// Pool options
	pool.MaxWait = 3 * time.Minute

	// Healthcheck
	err = pool.Client.Ping()
	require.NoError(t, err)

	// Container options
	require.NoError(t, err)

	options := &dockertest.RunOptions{
		Repository: "flutter-docker-image-windows-test",
		Tag:        "latest",
	}

	resource, err := pool.RunWithOptions(options)
	require.NoError(t, err)

	t.Cleanup(func() {
		require.NoError(t, pool.Purge(resource))
	})

	// var stdout bytes.Buffer
	// exitCode, err := resource.Exec(
	// 	[]string{"powershell.exe", "-Command", "Invoke-Pester -Configuration @{Run=@{Path='.\\test'; Exit=$true}; Output=@{Verbosity='Detailed'}}"},
	// 	dockertest.ExecOptions{
	// 		// StdOut: os.Stdout,
	// 		// StdErr: os.Stderr,
	// 		// TTY:    true,
	// 	},
	// )

	// require.NoError(t, err)
	// require.Zero(t, exitCode)
	// require.Equal(t, "bar", stdout.String())
}
