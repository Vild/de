module de.textbuffer;

import std.variant : Algebraic;

import de.container;
import de.pixelmap;
import de.textrenderer;

enum TextStyle {
	none = 0,
	bold = 1 << 0,
	underscore = 1 << 1,
	italic = 1 << 2
}

struct TextPart {
	dstring text;
	TextStyle style;
	size_t fontSize;
	Color fg, bg;

	Vec2!ulong getSize(FreeType ft) {
		return ft.getSize(text, style, fontSize);
	}
}

struct Line {
	alias Data = Algebraic!(TextPart, PixelMap);
	Data[] parts;

	Vec2!ulong getSize(FreeType ft) {
		import std.algorithm : max;

		Vec2!ulong size;
		foreach (p; parts) {
			Vec2!ulong s;
			if (auto _ = p.peek!TextPart)
				s = _.getSize(ft);
			else if (auto _ = p.peek!PixelMap)
				s = _.getSize();

			size.x += s.x;
			size.y = size.y.max(s.y);
		}
		return size;
	}
}

class TextBuffer {
public:
	 ~this() {
		foreach (Line* l; _lines)
			l.destroy;
	}

	void clear() {
		foreach (Line* l; _lines)
			l.destroy;
		_lines = null;
	}

	void addLine(size_t idx, dstring text, size_t fontSize, Color fg = Color(255, 255, 255, 255), Color bg = Color(0, 34, 34, 255)) {
		Line* line = new Line();
		line.parts = [Line.Data(TextPart(text, TextStyle.none, fontSize, fg, bg))];
		return addLine(idx, line);
	}

	void addLine(size_t idx, PixelMap pixelMap) {
		Line* line = new Line();
		line.parts = [Line.Data(pixelMap)];
		return addLine(idx, line);
	}

	void addLine(size_t idx, Line* line) {
		import core.stdc.string : memmove;

		if (idx >= _lines.length) {
			_lines ~= line;
			return;
		}

		_lines ~= null;
		memmove(&_lines[idx + 1], &_lines[idx], (_lines.length - idx - 1) * _lines[0].sizeof);
		_lines[idx] = line;
	}

	void removeLine(size_t idx) {
		import core.stdc.string : memmove;

		memmove(&_lines[idx], &_lines[idx + 1], (_lines.length - idx - 1) * _lines[0].sizeof);
		_lines.length--;
	}

	void swap_Lines(size_t a, size_t b) {
		Line* tmp = _lines[a];
		_lines[a] = _lines[b];
		_lines[b] = tmp;
	}

	@property ref Line*[] lines() {
		return _lines;
	}

private:
	Line*[] _lines;

}
