module stdx.string;

import std.traits : isNumeric;

import derelict.utf8proc.utf8proc;

shared static this() {
	DerelictUTF8Proc.load();
}

char[] numberToString(T)(char[] buf, T number, size_t base = 10) if (isNumeric!T) {
	static string chars = "0123456789ABCDEF";
	assert(base <= chars.length);
	bool negative = number < 0;
	if (negative)
		number = -number;

	size_t count;
	while (number > 0) {
		buf[buf.length - ++count] = chars[number % base];
		number /= base;
	}
	if (negative)
		buf[buf.length - ++count] = '-';

	return buf[buf.length - count .. $];
}

int getCharSize(dchar ch) {
	import std.format;

	auto r = utf8proc_charwidth(ch);
	//assert(r > 0, format("'0x%X' returned <= 0", cast(uint)ch));
	return r;
}

size_t getStringWidth(string str) {
	import std.uni;

	size_t len;

	foreach (Grapheme grapheme; str.byGrapheme) {
		debug foreach (ch; grapheme[][1 .. $])
			assert(ch.getCharSize == 0);

		len += grapheme[0].getCharSize;
	}
	return len;
}

struct Character {
	import std.uni;

	Grapheme grapheme;

	alias grapheme this;

	@property size_t renderWidth() {
		import std.algorithm : min;

		return min(1, grapheme[0].getCharSize);
	}

	@property size_t dataSize() {
		import std.utf : codeLength;

		size_t size;

		foreach (ch; grapheme)
			size += ch.codeLength!char;

		return size;
	}
}

struct UTFString {
	import std.uni;
	import std.traits;
	import std.range : ElementType;

	private char[] _utf8Data;
	private size_t _position;

	this(char[] utf8Data, size_t position) {
		_utf8Data = utf8Data;
		_position = position;
	}

	this(String)(String str) if (isSomeChar!(ElementType!String)) {
		import std.conv : to;

		_utf8Data = str.to!(char[]);
	}

	this(String)(String chars) if (is(ElementType!String == Character)) {
		import std.array : appender;

		auto app = appender!(char[]);
		foreach (ref Character c; chars)
			foreach (dchar ch; c.grapheme[])
				app.put(ch);

		_utf8Data = app.data;
	}

	private size_t toUTF8Offset(size_t idx) {
		import std.utf : codeLength;

		size_t len;
		auto r = _utf8Data.byGrapheme;

		while (idx && !r.empty) {
			Grapheme grapheme = r.front;
			foreach (ch; grapheme)
				len += ch.codeLength!char;
			idx--;

			r.popFront;
		}

		return len;
	}

	private size_t fromUTF8Offset(size_t offset) {
		import std.utf : codeLength;

		size_t len;
		size_t idx;
		auto r = _utf8Data.byGrapheme;

		while (idx && !r.empty) {
			Grapheme grapheme = r.front;
			foreach (ch; grapheme)
				len += ch.codeLength!char;
			idx++;

			if (len == offset)
				return idx;
			else if (len > offset)
				return idx - 1;

			r.popFront;
		}

		return idx;
	}

	void insert(C : dchar)(size_t idx, C[] chars) {
		import std.utf : byChar;
		import std.utf : codeLength;
		import core.stdc.string : memmove;

		auto offset = toUTF8Offset(idx);

		auto r = chars.byChar;

		_utf8Data.length += r.length;
		if (offset + r.length < _utf8Data.length) {
			auto to = &_utf8Data[offset + r.length];
			auto from = &_utf8Data[offset];

			memmove(to, from, _utf8Data.length - r.length - offset);
		}
		foreach (ch; r)
			_utf8Data[offset++] = ch;
	}

	@property Character front() {
		import std.utf : byDchar;

		auto r = _utf8Data[toUTF8Offset(_position) .. $].byDchar;
		return decodeGrapheme(r).Character;
	}

	void popFront() {
		_position++;
	}

	void reset() {
		_position = 0;
	}

	@property bool empty() {
		return toUTF8Offset(_position) >= _utf8Data.length;
	}

	@property UTFString save() {
		return UTFString(_utf8Data, _position);
	}

	@property size_t length() {
		import std.range.primitives : walkLength;

		return _utf8Data[toUTF8Offset(_position) .. $].byGrapheme.walkLength;
	}

	size_t opDollar(size_t pos : 0)() {
		return length;
	}

	Character opIndex(size_t idx) {
		import std.utf : byDchar;

		auto r = _utf8Data[toUTF8Offset(_position + idx) .. $].byDchar;
		return decodeGrapheme(r).Character;
	}

	auto opSlice(size_t x, size_t y) {
		import std.range : takeExactly;
		import std.algorithm : map;

		return _utf8Data[toUTF8Offset(_position + x) .. $].byGrapheme.map!((c) => Character(c)).takeExactly(y - x);
	}

	int opApply(scope int delegate(ref Character) dg) {
		int result = 0;
		auto r = save();

		while (!r.empty) {
			auto ch = r.front;
			result = dg(ch);
			if (result)
				break;
			r.popFront;
		}

		return result;
	}

	int opApply(scope int delegate(size_t, ref Character) dg) {
		int result = 0;
		auto r = save();

		size_t idx;
		while (!r.empty) {
			auto ch = r.front;
			result = dg(idx++, ch);
			if (result)
				break;
			r.popFront;
		}

		return result;
	}

	@property char[] rawData() {
		return _utf8Data[toUTF8Offset(_position) .. $];
	}
}
