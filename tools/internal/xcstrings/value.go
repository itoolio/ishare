package xcstrings

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sort"
)

type Kind int

const (
	Null Kind = iota
	Bool
	Number
	String
	Array
	Object
)

type Member struct {
	Key   string
	Value *Value
}

type Value struct {
	Kind    Kind
	Bool    bool
	Number  json.Number
	String  string
	Items   []*Value
	Members []Member
}

func NewString(text string) *Value {
	return &Value{Kind: String, String: text}
}

func NewObject(members ...Member) *Value {
	return &Value{Kind: Object, Members: members}
}

func (value *Value) Get(key string) *Value {
	if value == nil || value.Kind != Object {
		return nil
	}
	for _, member := range value.Members {
		if member.Key == key {
			return member.Value
		}
	}
	return nil
}

func (value *Value) Has(key string) bool {
	if value == nil || value.Kind != Object {
		return false
	}
	for _, member := range value.Members {
		if member.Key == key {
			return true
		}
	}
	return false
}

func (value *Value) Set(key string, item *Value) {
	for index, member := range value.Members {
		if member.Key == key {
			value.Members[index].Value = item
			return
		}
	}
	value.Members = append(value.Members, Member{Key: key, Value: item})
}

func (value *Value) SortMembers() {
	sort.SliceStable(value.Members, func(left, right int) bool {
		return value.Members[left].Key < value.Members[right].Key
	})
}

func (value *Value) IsFalse() bool {
	return value != nil && value.Kind == Bool && !value.Bool
}

func (value *Value) Text() (string, bool) {
	if value == nil || value.Kind != String {
		return "", false
	}
	return value.String, true
}

func Parse(data []byte) (*Value, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	value, err := decode(decoder)
	if err != nil {
		return nil, err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("unexpected data after the top-level value")
	}
	return value, nil
}

func decode(decoder *json.Decoder) (*Value, error) {
	token, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	return decodeToken(decoder, token)
}

func decodeToken(decoder *json.Decoder, token json.Token) (*Value, error) {
	switch typed := token.(type) {
	case nil:
		return &Value{Kind: Null}, nil
	case bool:
		return &Value{Kind: Bool, Bool: typed}, nil
	case json.Number:
		return &Value{Kind: Number, Number: typed}, nil
	case string:
		return NewString(typed), nil
	case json.Delim:
		if typed == '{' {
			return decodeObject(decoder)
		}
		if typed == '[' {
			return decodeArray(decoder)
		}
	}
	return nil, fmt.Errorf("unexpected token %v", token)
}

func decodeObject(decoder *json.Decoder) (*Value, error) {
	object := NewObject()
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		key, ok := token.(string)
		if !ok {
			return nil, fmt.Errorf("expected an object key, got %v", token)
		}
		item, err := decode(decoder)
		if err != nil {
			return nil, err
		}
		object.Set(key, item)
	}
	if _, err := decoder.Token(); err != nil {
		return nil, err
	}
	return object, nil
}

func decodeArray(decoder *json.Decoder) (*Value, error) {
	array := &Value{Kind: Array, Items: []*Value{}}
	for decoder.More() {
		item, err := decode(decoder)
		if err != nil {
			return nil, err
		}
		array.Items = append(array.Items, item)
	}
	if _, err := decoder.Token(); err != nil {
		return nil, err
	}
	return array, nil
}
