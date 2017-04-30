module de.textbuffer;

import std.variant : Algebraic;

import de.pixelmap;

struct TextLine {
	dstring text;
	size_t height;
	//TODO: custom font stuff
}

struct Line {
	alias Data = Algebraic!(TextLine, PixelMap);
	Data data;

	@property size_t height() {
		if (auto _ = data.peek!TextLine)
			return _.height;
		else if (auto _ = data.peek!PixelMap)
			return _.height;
		else
			assert(0);
	}
}

class TextBuffer {
public:
	 ~this() {
		foreach (Line* l; _lines)
			l.destroy;
	}

	void addLine(size_t idx, dstring text, size_t height) {
		return addLine(idx, new Line(Line.Data(TextLine(text, height))));
	}

	void addLine(size_t idx, PixelMap pixelMap) {
		return addLine(idx, new Line(Line.Data(pixelMap)));
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
