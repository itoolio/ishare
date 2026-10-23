package releasecheck

import (
	"fmt"
	"image"
	"image/color"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	ScreenshotWidth      = 2880
	ScreenshotHeight     = 1800
	maximumScreenshots   = 10
	screenshotExtensions = ".jpg.jpeg.png"
)

func CheckScreenshots(directory string) []string {
	locales, err := os.ReadDir(directory)
	if err != nil {
		return []string{fmt.Sprintf("couldn't read %s: %v", directory, err)}
	}
	var problems []string
	found := 0
	for _, locale := range locales {
		if !locale.IsDir() {
			continue
		}
		files, err := screenshotFiles(filepath.Join(directory, locale.Name()))
		if err != nil {
			problems = append(problems, err.Error())
			continue
		}
		if len(files) > maximumScreenshots {
			problems = append(problems, fmt.Sprintf("%s has %d screenshots, the App Store allows %d", locale.Name(), len(files), maximumScreenshots))
		}
		for _, file := range files {
			found++
			problems = append(problems, checkScreenshot(file)...)
		}
	}
	if found == 0 {
		problems = append(problems, fmt.Sprintf("there are no committed screenshots in %s", directory))
	}
	return problems
}

func screenshotFiles(directory string) ([]string, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, err
	}
	var files []string
	for _, entry := range entries {
		extension := strings.ToLower(filepath.Ext(entry.Name()))
		if entry.IsDir() || extension == "" || !strings.Contains(screenshotExtensions, extension) {
			continue
		}
		files = append(files, filepath.Join(directory, entry.Name()))
	}
	sort.Strings(files)
	return files, nil
}

func checkScreenshot(path string) []string {
	file, err := os.Open(path)
	if err != nil {
		return []string{err.Error()}
	}
	defer file.Close()
	config, format, err := image.DecodeConfig(file)
	if err != nil {
		return []string{fmt.Sprintf("%s is not a readable image: %v", path, err)}
	}
	var problems []string
	if config.Width != ScreenshotWidth || config.Height != ScreenshotHeight {
		problems = append(problems, fmt.Sprintf("%s is %dx%d, App Store screenshots must be %dx%d", path, config.Width, config.Height, ScreenshotWidth, ScreenshotHeight))
	}
	if hasAlpha(config.ColorModel) {
		problems = append(problems, fmt.Sprintf("%s is a %s with an alpha channel, App Store screenshots must be opaque", path, strings.ToUpper(format)))
	}
	return problems
}

func hasAlpha(model color.Model) bool {
	switch model {
	case color.RGBAModel, color.RGBA64Model, color.NRGBAModel, color.NRGBA64Model, color.AlphaModel, color.Alpha16Model:
		return true
	}
	if palette, ok := model.(color.Palette); ok {
		for _, entry := range palette {
			if _, _, _, alpha := entry.RGBA(); alpha != 0xffff {
				return true
			}
		}
	}
	return false
}
