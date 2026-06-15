"""Tolerant JSON / JSONC / JSON5-ish parser.

Supports:
  - standard JSON (objects, arrays, strings, numbers, true/false/null)
  - // line comments and /* */ block comments
  - trailing commas in objects and arrays
  - unquoted (bare identifier) object keys

Returns the parsed Python value tree PLUS a `spans` dict mapping a
key-path tuple (dict keys as str, list indices as int) to the
(start, end) character offsets of that leaf's VALUE TOKEN in the
original text. Only scalar leaves (str/int/float/bool/None) get spans;
objects/arrays are not leaves.
"""

import json
import re


class ParseError(Exception):
    pass


_WS_RE = re.compile(r"\s+")

_TOKEN_RE = re.compile(r"""
      (?P<STRING>"(?:\\.|[^"\\])*")
    | (?P<NUMBER>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)
    | (?P<LBRACE>\{)
    | (?P<RBRACE>\})
    | (?P<LBRACKET>\[)
    | (?P<RBRACKET>\])
    | (?P<COLON>:)
    | (?P<COMMA>,)
    | (?P<IDENT>[A-Za-z_$][A-Za-z0-9_$]*)
""", re.VERBOSE)

_INT_RE = re.compile(r"-?\d+\Z")


def _skip_ws_comments(text, pos):
    n = len(text)
    while pos < n:
        m = _WS_RE.match(text, pos)
        if m:
            pos = m.end()
            continue
        if text.startswith("//", pos):
            nl = text.find("\n", pos)
            pos = n if nl == -1 else nl + 1
            continue
        if text.startswith("/*", pos):
            end = text.find("*/", pos + 2)
            if end == -1:
                raise ParseError("unterminated block comment")
            pos = end + 2
            continue
        return pos
    return pos


def _tokenize(text):
    pos = 0
    n = len(text)
    tokens = []
    while True:
        pos = _skip_ws_comments(text, pos)
        if pos >= n:
            break
        m = _TOKEN_RE.match(text, pos)
        if not m:
            snippet = text[pos:pos + 30]
            raise ParseError(f"unexpected character at offset {pos}: {snippet!r}")
        tokens.append((m.lastgroup, m.group(), m.start(), m.end()))
        pos = m.end()
    return tokens


class _Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.i = 0
        self.spans = {}

    def _peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def _advance(self):
        t = self.tokens[self.i]
        self.i += 1
        return t

    def _expect(self, kind):
        t = self._peek()
        if t is None or t[0] != kind:
            raise ParseError(f"expected {kind}, got {t}")
        return self._advance()

    def parse_value(self, path):
        t = self._peek()
        if t is None:
            raise ParseError("unexpected end of input")
        kind, text, start, end = t

        if kind == "LBRACE":
            return self._parse_object(path)
        if kind == "LBRACKET":
            return self._parse_array(path)
        if kind == "STRING":
            self._advance()
            val = json.loads(text)
            self.spans[path] = (start, end)
            return val
        if kind == "NUMBER":
            self._advance()
            val = int(text) if _INT_RE.match(text) else float(text)
            self.spans[path] = (start, end)
            return val
        if kind == "IDENT":
            self._advance()
            if text == "true":
                val = True
            elif text == "false":
                val = False
            elif text == "null":
                val = None
            else:
                raise ParseError(f"unexpected identifier {text!r} used as a value")
            self.spans[path] = (start, end)
            return val

        raise ParseError(f"unexpected token {kind} {text!r}")

    def _parse_object(self, path):
        self._expect("LBRACE")
        d = {}
        t = self._peek()
        if t and t[0] == "RBRACE":
            self._advance()
            return d
        while True:
            t = self._peek()
            if t is None:
                raise ParseError("unexpected end of input inside object")
            if t[0] == "STRING":
                self._advance()
                key = json.loads(t[1])
            elif t[0] == "IDENT":
                self._advance()
                key = t[1]
            else:
                raise ParseError(f"expected an object key, got {t}")
            self._expect("COLON")
            d[key] = self.parse_value(path + (key,))
            t = self._peek()
            if t and t[0] == "COMMA":
                self._advance()
                t2 = self._peek()
                if t2 and t2[0] == "RBRACE":
                    self._advance()
                    return d
                continue
            self._expect("RBRACE")
            return d

    def _parse_array(self, path):
        self._expect("LBRACKET")
        arr = []
        t = self._peek()
        if t and t[0] == "RBRACKET":
            self._advance()
            return arr
        idx = 0
        while True:
            arr.append(self.parse_value(path + (idx,)))
            idx += 1
            t = self._peek()
            if t and t[0] == "COMMA":
                self._advance()
                t2 = self._peek()
                if t2 and t2[0] == "RBRACKET":
                    self._advance()
                    return arr
                continue
            self._expect("RBRACKET")
            return arr


def parse_jsonc(text):
    """Parse JSON/JSONC/JSON5-ish `text`.

    Returns (tree, spans). Raises ParseError on malformed input."""
    tokens = _tokenize(text)
    if not tokens:
        raise ParseError("empty input")
    p = _Parser(tokens)
    value = p.parse_value(())
    if p.i != len(tokens):
        extra = tokens[p.i]
        raise ParseError(f"unexpected trailing token {extra}")
    return value, p.spans
