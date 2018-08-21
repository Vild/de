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
	import std.range;
	import std.stdio;

	size_t len;

	foreach (Grapheme grapheme; str.byGrapheme) {
		foreach (ch; grapheme[][1 .. $])
			assert(ch.getCharSize == 0);

		len += grapheme[0].getCharSize;
	}
	return len;
}
