package plist

import (
	"encoding/base64"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
)

func Parse(data []byte) (any, error) {
	decoder := xml.NewDecoder(strings.NewReader(string(data)))
	decoder.Strict = false
	for {
		token, err := decoder.Token()
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("the property list is empty")
		}
		if err != nil {
			return nil, err
		}
		start, ok := token.(xml.StartElement)
		if !ok || start.Name.Local == "plist" {
			continue
		}
		return parseValue(decoder, start)
	}
}

func ParseDictionary(data []byte) (map[string]any, error) {
	value, err := Parse(data)
	if err != nil {
		return nil, err
	}
	dictionary, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("the property list is not a dictionary")
	}
	return dictionary, nil
}

func parseValue(decoder *xml.Decoder, start xml.StartElement) (any, error) {
	switch start.Name.Local {
	case "dict":
		return parseDictionary(decoder)
	case "array":
		return parseArray(decoder)
	case "true", "false":
		if err := decoder.Skip(); err != nil {
			return nil, err
		}
		return start.Name.Local == "true", nil
	}
	text, err := readText(decoder)
	if err != nil {
		return nil, err
	}
	switch start.Name.Local {
	case "string", "date":
		return text, nil
	case "integer":
		return strconv.ParseInt(strings.TrimSpace(text), 10, 64)
	case "real":
		return strconv.ParseFloat(strings.TrimSpace(text), 64)
	case "data":
		return base64.StdEncoding.DecodeString(strings.Join(strings.Fields(text), ""))
	}
	return nil, fmt.Errorf("unsupported property list element <%s>", start.Name.Local)
}

func parseDictionary(decoder *xml.Decoder) (map[string]any, error) {
	dictionary := map[string]any{}
	var key *string
	for {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		switch element := token.(type) {
		case xml.EndElement:
			return dictionary, nil
		case xml.StartElement:
			if element.Name.Local == "key" {
				text, err := readText(decoder)
				if err != nil {
					return nil, err
				}
				key = &text
				continue
			}
			if key == nil {
				return nil, fmt.Errorf("a dictionary value has no key")
			}
			value, err := parseValue(decoder, element)
			if err != nil {
				return nil, err
			}
			dictionary[*key] = value
			key = nil
		}
	}
}

func parseArray(decoder *xml.Decoder) ([]any, error) {
	array := []any{}
	for {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		switch element := token.(type) {
		case xml.EndElement:
			return array, nil
		case xml.StartElement:
			value, err := parseValue(decoder, element)
			if err != nil {
				return nil, err
			}
			array = append(array, value)
		}
	}
}

func readText(decoder *xml.Decoder) (string, error) {
	var builder strings.Builder
	for {
		token, err := decoder.Token()
		if err != nil {
			return "", err
		}
		switch element := token.(type) {
		case xml.CharData:
			builder.Write(element)
		case xml.EndElement:
			return builder.String(), nil
		case xml.StartElement:
			return "", fmt.Errorf("unexpected <%s> inside a text value", element.Name.Local)
		}
	}
}
