module de.line;

import de.utfstring : UTFString, Character, numberToString;
import de.terminal : Color;
import de.build : Config;

import std.format : format;

struct TextStyle {
	bool bright; // 1
	bool dim; // 2
	bool italic; // 3
	bool underscore; // 4
	bool blink; // 5
	bool reverse; // 7
	bool crossedOut; // 9
	bool overscore; // 53

	Color fg = Color.brightWhite; //Color.defaultColor;
	Color bg = Color.defaultColor; // + 10

	void toString(scope void delegate(const(char)[]) sink) {
		static char[64 * 8] buf;

		sink("\x1b[");
		if (bright)
			sink("1;");
		if (dim)
			sink("2;");
		if (italic)
			sink("3;");
		if (underscore)
			sink("4;");
		if (blink)
			sink("5;");
		if (reverse)
			sink("7;");
		if (crossedOut)
			sink("9;");
		if (overscore)
			sink("53;");

		sink(numberToString(buf, fg));
		sink(";");
		sink(numberToString(buf, bg + 10));
		sink("m");
	}
}

struct Line {
	struct Part {
		TextStyle style;
		UTFString str;
		bool special;

		@property size_t length() {
			return str.length;
		}

		@property size_t renderWidth() {
			return str.renderedWidth;
		}

		size_t opDollar(size_t pos : 0)() {
			return renderedWidth;
		}

		string opSlice(size_t x, size_t y) {
			import std.array : appender;

			auto output = appender!string;
			slice((str) => output ~= str, x, y);
			return output.data();
		}

		void slice(scope void delegate(const(char)[]) sink, size_t x, size_t y) {
			assert(x < y, format("%d < %d", x, y));
			assert(x <= renderWidth, format(", y=%d), x=%d is outside of string(len: %d)", y, x, renderWidth));
			assert(y <= renderWidth, format(", x=%d), y=%d is outside of string(len: %d)", x, y, renderWidth));

			style.toString(sink);
			if (x < renderWidth) {
				import std.range : take, popFrontN;
				import std.utf : byDchar;
				import std.uni : Grapheme;
				import std.algorithm : each;
				import std.conv : to;

				auto skipCharWidth(R)(R range, size_t width) {
					import std.range : chain, repeat;

					Character spaceCharacter;
					spaceCharacter = Character(Grapheme(" "));

					size_t widthCounter;
					while (widthCounter < width && !range.empty) {
						Character ch = range.front;
						widthCounter += ch.renderWidth;
						range.popFront;
					}

					if (range.empty)
						return chain(repeat(spaceCharacter, 0), range);

					size_t offset = widthCounter - width;

					return chain(repeat(spaceCharacter, offset), range);
				}

				auto takeCharWidth(R)(R range, long width) {
					struct Take {
						R range;
						long width;

						void popFront() {
							width -= range.front.renderWidth;
							range.popFront;
						}

						@property auto front() {
							return range.front;
						}

						@property bool empty() {
							return range.empty || range.front.renderWidth > width;
						}
					}

					return Take(range, width);
				}

				UTFString s = str.save;

				string output;
				// dfmt off
				takeCharWidth(skipCharWidth(s, x), y - x)
					.each!((Character g) =>
						g.grapheme.each!((x) =>
							output ~= x
						)
				);
				// dfmt on
				sink(output);
			}
			sink("\x1b[0m");
		}
	}

	enum RenderStyle {
		normal, // Compact
		fillWidth, // Will entire line with last parts style
	}

	UTFString text;
	Part[] textParts;
	RenderStyle renderStyle;

	@property size_t length() {
		import std.algorithm : map, sum;

		return textParts.map!"a.length".sum;
	}

	@property size_t renderWidth() {
		import std.algorithm : map, sum;

		return textParts.map!"a.renderWidth".sum;
	}

	void addChar(size_t idx, dchar ch) {
		import std.utf : encode;

		char[4] buf;
		auto len = encode(buf, ch);
		text.insert(idx, buf[0 .. len]);
		refresh();
	}

	void removeChar(size_t idx) {
		text.remove(idx);
		refresh();
	}

	size_t opDollar(size_t pos : 0)() {
		return renderedWidth;
	}

	string opSlice(size_t x, size_t y) {
		import std.array : appender;

		auto output = appender!string;
		slice((str) => output ~= str, x, y);
		return output.data();
	}

	void slice(scope void delegate(const(char)[]) sink, size_t x, size_t y) {
		import std.range : empty, popFront, front;

		Part[] parts = textParts;

		if (parts.empty || x == y)
			return;

		// Step 1. discard parts until x is a valid location in part
		while (!parts.empty && x && x < y && x > parts[0].renderWidth) {
			x -= parts[0].renderWidth;
			y -= parts[0].renderWidth;
			parts.popFront;
		}

		if (parts.empty)
			return;

		// Step 2 Get data so X becomes 0
		if (!parts.empty && x) {
			Part part = parts.front;
			parts.popFront;

			size_t sizeWant = y - x;
			if (part.renderWidth - x < sizeWant) // Won't find all the requested data in this part
				sizeWant = part.renderWidth - x;

			sink(part[x .. sizeWant + x]);
			x = 0;
			y -= sizeWant;
		}

		if (parts.empty)
			return;

		// Step 3 Continue to get data until y = 0
		while (!parts.empty && y) {
			Part part = parts.front;
			parts.popFront;

			size_t sizeWant = y;
			if (part.renderWidth < sizeWant) // Won't find all the requested data in this part
				sizeWant = part.renderWidth;

			sink(part[x .. sizeWant]);

			y -= sizeWant;
		}
	}

	void refresh() {
		import std.string : indexOf;
		import std.algorithm : filter, sum;
		import std.range : empty, repeat;
		import std.utf : toUTF8;

		textParts.length = 0;
		size_t idx;
		bool wasSpace;
		bool wasChar;

		UTFString str = text.save;

		alias isTab = (ch) => ch.grapheme[0] == '\t';
		alias isSpace = (ch) => ch.grapheme[0] == ' ' && !wasChar;
		/*alias isSpace = (ch) => ch == ' ' && (!wasChar || (wasChar && textParts[$ - 1].str.length > 1
					&& textParts[$ - 1].str[$ - 2] == '/' && (textParts[$ - 1].str[$ - 1] == '/' || textParts[$ - 1].str[$ - 1] == '*')));*/
		while (!str.empty) {
			auto ch = str.front;
			if (isTab(ch)) {
				import std.array : insertInPlace;
				import std.range : repeat;

				Part part;
				part.style.fg = Color.white;
				part.style.dim = true;
				if (wasSpace) {
					textParts[$ - 1].style.bg = Color.brightYellow;
					textParts[$ - 1].style.dim = false;
				}

				size_t tabCount;

				do {
					tabCount++;

					str.popFront;
					if (str.empty)
						break;
					ch = str.front;
				}
				while (isTab(ch));

				const size_t numberOfSpaces = (Config.tabSize) - (idx % Config.tabSize) + (Config.tabSize * (tabCount - 1));
				wchar[] buf = new wchar[numberOfSpaces];
				scope (exit)
					buf.destroy;
				foreach (i, ref c; buf)
					if ((idx + i - 1) % Config.tabSize)
						c = Config.tabCharStart;
					else if (!i)
						c = Config.tabCharStartUnaligned;
					else if ((idx + i - 2) % Config.tabSize)
						c = Config.tabEnd;
					else
						c = Config.tabMiddle;
				idx += numberOfSpaces;
				part.str = UTFString(buf);

				wasSpace = false;
				wasChar = false;

				textParts ~= part;
			} else if (isSpace(ch)) {
				Part part;
				part.style.fg = Color.white;
				part.style.dim = true;

				size_t spaceCount;

				do {
					spaceCount++;
					idx++;

					str.popFront;
					if (str.empty)
						break;
					ch = str.front;
				}
				while (isSpace(ch));

				part.str = UTFString(repeat(Config.spaceChar, spaceCount));

				wasSpace = true;
				wasChar = false;

				textParts ~= part;
			} else {
				Part part;

				size_t charCount;
				auto textStart = str.save;

				do {
					charCount++;
					idx++;

					str.popFront;
					if (str.empty)
						break;
					ch = str.front;
				}
				while (!isTab(ch) && !isSpace(ch));

				part.str = UTFString(textStart[0 .. charCount]);

				wasSpace = false;
				wasChar = true;

				textParts ~= part;
			}
		}
	}

	long indexToColumn(long dataIdx) {
		size_t idx;
		size_t dataCount;
		foreach (ref Character ch; text) {
			if (dataCount >= dataIdx)
				break;
			if (ch.length == 1 && ch[0] == '\t')
				idx += (Config.tabSize - 1) - (idx % Config.tabSize) + 1;
			else
				idx += ch.renderWidth;

			dataCount++;
		}
		return idx;
	}

	long columnToIndex(long column) {
		if (!column)
			return 0;

		size_t idx;
		size_t i;
		foreach (ref Character ch; text) {
			if (ch.length == 1 && ch[0] == '\t')
				idx += (Config.tabSize - 1) - (idx % Config.tabSize) + 1;
			else
				idx += ch.renderWidth;

			if (column == idx)
				return i + 1;
			else if (column < idx)
				return i;

			i++;
		}
		return column;
	}
}
