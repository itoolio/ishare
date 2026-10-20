package repo

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func Root() string {
	_, source, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(source), "..", "..", ".."))
}

func Path(parts ...string) string {
	return filepath.Join(append([]string{Root()}, parts...)...)
}

func Run(directory string, name string, arguments ...string) error {
	command := exec.Command(name, arguments...)
	command.Dir = directory
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s failed: %w", name, err)
	}
	return nil
}

func Fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
