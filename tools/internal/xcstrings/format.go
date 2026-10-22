package xcstrings

import (
	"fmt"
	"strconv"
	"strings"
)

func Format(value *Value) []byte {
	var builder strings.Builder
	write(&builder, value, 0)
	return []byte(builder.String())
}

func write(builder *strings.Builder, value *Value, depth int) {
	switch value.Kind {
	case Object:
		writeObject(builder, value.Members, depth)
	case Array:
		writeArray(builder, value.Items, depth)
	case String:
		builder.WriteString(quote(value.String))
	case Number:
		builder.WriteString(formatNumber(string(value.Number)))
	case Bool:
		builder.WriteString(strconv.FormatBool(value.Bool))
	default:
		builder.WriteString("null")
	}
}

func writeObject(builder *strings.Builder, members []Member, depth int) {
	if len(members) == 0 {
		builder.WriteString("{\n\n" + indent(depth) + "}")
		return
	}
	builder.WriteString("{\n")
	for index, member := range members {
		if index > 0 {
			builder.WriteString(",\n")
		}
		builder.WriteString(indent(depth+1) + quote(member.Key) + " : ")
		write(builder, member.Value, depth+1)
	}
	builder.WriteString("\n" + indent(depth) + "}")
}

func writeArray(builder *strings.Builder, items []*Value, depth int) {
	if len(items) == 0 {
		builder.WriteString("[\n\n" + indent(depth) + "]")
		return
	}
	builder.WriteString("[\n")
	for index, item := range items {
		if index > 0 {
			builder.WriteString(",\n")
		}
		builder.WriteString(indent(depth + 1))
		write(builder, item, depth+1)
	}
	builder.WriteString("\n" + indent(depth) + "]")
}

func indent(depth int) string {
	return strings.Repeat("  ", depth)
}

func quote(text string) string {
	var builder strings.Builder
	builder.WriteByte('"')
	for _, character := range text {
		switch character {
		case '"':
			builder.WriteString(`\"`)
		case '\\':
			builder.WriteString(`\\`)
		case '\b':
			builder.WriteString(`\b`)
		case '\f':
			builder.WriteString(`\f`)
		case '\n':
			builder.WriteString(`\n`)
		case '\r':
			builder.WriteString(`\r`)
		case '\t':
			builder.WriteString(`\t`)
		default:
			if character < 0x20 {
				fmt.Fprintf(&builder, `\u%04x`, character)
			} else {
				builder.WriteRune(character)
			}
		}
	}
	builder.WriteByte('"')
	return builder.String()
}

func formatNumber(literal string) string {
	if !strings.ContainsAny(literal, ".eE") {
		return literal
	}
	number, err := strconv.ParseFloat(literal, 64)
	if err != nil {
		return literal
	}
	return pythonFloat(number)
}

func pythonFloat(number float64) string {
	scientific := strconv.FormatFloat(number, 'e', -1, 64)
	exponent, _ := strconv.Atoi(scientific[strings.IndexByte(scientific, 'e')+1:])
	if number != 0 && (exponent < -4 || exponent >= 16) {
		return scientific
	}
	plain := strconv.FormatFloat(number, 'f', -1, 64)
	if !strings.Contains(plain, ".") {
		plain += ".0"
	}
	return plain
}
