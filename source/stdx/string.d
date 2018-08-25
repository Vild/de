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

	private Character _front;
	private size_t _length;

	private void _refreshData() {
		import std.utf : byDchar;
		import std.range.primitives : walkLength;

		auto r = _utf8Data[toUTF8Offset(_position) .. $].byDchar;
		_front = decodeGrapheme(r).Character;

		_length = _utf8Data[toUTF8Offset(_position) .. $].byGrapheme.walkLength;
	}

	this(char[] utf8Data, size_t position) {
		_utf8Data = utf8Data;
		_position = position;
		if (_utf8Data.length)
			_refreshData();
	}

	this(String)(String str) if (isSomeChar!(ElementType!String)) {
		import std.conv : to;

		_utf8Data = str.to!(char[]);
		if (_utf8Data.length)
			_refreshData();
	}

	this(String)(String chars) if (is(ElementType!String == Character)) {
		import std.array : appender;

		auto app = appender!(char[]);
		foreach (ref Character c; chars)
			foreach (dchar ch; c.grapheme[])
				app.put(ch);

		_utf8Data = app.data;
		if (_utf8Data.length)
			_refreshData();
	}

	private size_t toUTF8Offset(size_t idx) {
		size_t len;

		while (idx && len < _utf8Data.length) {
			len += _utf8Data.graphemeStride(len);
			idx--;
		}

		return len;
	}

	private size_t fromUTF8Offset(size_t offset) {
		size_t len;
		size_t idx;

		while (idx && len < _utf8Data.length) {
			len += _utf8Data.graphemeStride(len);
			idx++;

			if (len == offset)
				return idx;
			else if (len > offset)
				return idx - 1;
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
		return _front;
	}

	void popFront() {
		_position++;

		if (empty) {
			_front = Character.init;
			_length = 0;
		} else
			_refreshData();
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
		return _length;
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
