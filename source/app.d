import core.sys.posix.unistd;
import core.sys.posix.termios;
import core.sys.posix.sys.ioctl;
import core.sys.posix.signal;
import core.sys.posix.fcntl;

import core.stdc.ctype;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.errno;

import core.time;

import std.format : format;
import std.traits : isNumeric;

import stdx.string;

alias CTRL_KEY = (char k) => cast(Key)((k) & 0x1f);

static struct Build {
static:
	enum string version_ = "0.0.1";
}

static struct Config {
static:
	size_t tabSize = 2;

	wchar tabCharStart = '↦';
	wchar tabCharStartUnaligned = '↦';
	wchar tabMiddle = ' ';
	wchar tabEnd = ' ';

	wchar spaceChar = '⬩';
}

bool isTextChar(Key k) {
	import core.stdc.ctype : iscntrl;

	return !!iscntrl(cast(int)k);
}

enum Key : long {
	unknown = 0,

	return_ = '\r',
	backspace = 0x7f,
	escape = 0x1b,

	lettersEnd = 0xFFFF_0000,
	arrowUp,
	arrowDown,
	arrowLeft,
	arrowRight,

	delete_,
	home,
	end,
	pageUp,
	pageDown
}

static struct Terminal {
	@disable this();
public static:
	void init() {
		winsize ws;
		sigaction_t sa;

		sigemptyset(&sa.sa_mask);
		sa.sa_flags = 0;
		sa.sa_handler = &_refreshSize;
		version (CRuntime_Glibc) enum SIGWINCH = 28;
		if (sigaction(SIGWINCH, &sa, null) == -1)
			die("sigaction");

		version (unittest) {
		} else
			_enableRawMode();
		clear();
		_refreshSize(0);
	}

	extern (C) void destroy() {
		static bool called;
		if (called)
			return;
		called = true;
		version (unittest) {
		} else
			_disableRawMode();
		printf("\x1b[1mThank you for using DE - Powered by https://dlang.org/\x1b[0m\n");
	}

	void die(string s, string file = __FILE__, size_t line = __LINE__) {
		import std.string : toStringz;
		import std.format : format;

		_disableRawMode();

		perror(format("[%s:%3d] %s", file, line, s).toStringz);
		exit(errno ? errno : -1);
	}

	void write(Line line, size_t width = size_t.max) {
		size_t lineLen = line.length;
		if (lineLen > width)
			lineLen = width;

		line.slice((str) { _buffer ~= str; }, 0, lineLen);

		if (lineLen < _size[0] && line.renderStyle == Line.RenderStyle.fillWidth) {
			line.textParts[$ - 1].style.toString((str) { _buffer ~= str; });
			while (lineLen++ != _size[0])
				_buffer ~= ' ';
			_buffer ~= "\x1b[0m";
		}
	}

	void write(string str) {
		_buffer ~= str;
	}

	void write(const(char[]) str) {
		_buffer ~= str;
	}

	void write(T)(T num) if (isNumeric!T) {
		import stdx.string : numberToString;

		static char[64 * 8] buffer;
		_buffer ~= numberToString(buffer, num, 10);
	}

	void flush() {
		import std.string : toStringz;

		.write(STDOUT_FILENO, _buffer.toStringz, _buffer.length);
		_buffer.length = 0;
	}

	Key read() {
		char readCh(bool waitForChar)() {
			char c = '\0';
			static if (waitForChar) {
				long nread;
				while ((nread = .read(STDIN_FILENO, &c, 1)) != 1) {
					if (nread == -1 && errno != EAGAIN && errno != EINTR)
						Terminal.die("read");
				}
			} else if (.read(STDIN_FILENO, &c, 1) == -1 && errno != EAGAIN && errno != EINTR)
				Terminal.die("read");
			return c;
		}

		Key actionKeys(char c) {
			switch (c) {
			case '3':
				return Key.delete_;
			case '1':
			case '7':
			case 'H':
				return Key.home;
			case '8':
			case '4':
			case 'F':
				return Key.end;

			case '5':
				return Key.pageUp;
			case '6':
				return Key.pageDown;
			default:
				return Key.unknown;
			}
		}

		Key arrowKeys(char c) {
			switch (c) {
			case 'A':
				return Key.arrowUp;
			case 'B':
				return Key.arrowDown;
			case 'C':
				return Key.arrowRight;
			case 'D':
				return Key.arrowLeft;
			case 'H':
				return Key.home;
			case 'F':
				return Key.end;
			default:
				return Key.unknown;
			}
		}

		char c = readCh!false();
		if (c == '\x1b') {
			char seq0 = readCh!false();
			if (seq0 == '\0')
				return cast(Key)c;
			char seq1 = readCh!false();
			if (seq1 == '\0')
				return cast(Key)c;

			if (seq0 == '[') {
				switch (seq1) {
				case '0': .. case '9':
					char seq2 = readCh!false();
					if (seq2 != '~')
						break;
					return actionKeys(seq1);
				case 'A': .. case 'D':
				case 'H':
				case 'F':
					return arrowKeys(seq1);
				default:
					break;
				}
			} else if (seq0 == 'O') {
				return arrowKeys(seq1);
			}
		}
		return cast(Key)c;
	}

	void moveTo(long x = 0, long y = 0) {
		write("\x1b[");
		write(y + 1);
		write(";");
		write(x + 1);
		write("H");
	}

	void clear() {
		TextStyle t;

		write("\x1b[");
		write(cast(size_t)t.fg);
		write(";");
		write(cast(size_t)(t.bg + 10));
		write("m\x1b[2J\x1b[0m");
	}

	void clearLine() {
		TextStyle t;

		write("\x1b[");
		write(cast(size_t)(t.bg + 10));
		write("m\x1b[K\x1b[0m");
	}

	@property void cursorVisibility(bool v) {
		write("\x1b[?25");
		if (v)
			write("h");
		else
			write("l");
	}

	@property bool gotResized() {
		if (_newSize[0] != long.max) {
			_size = _newSize;
			_newSize = [long.max, long.max];
			return true;
		} else
			return false;
	}

	@property long[2] size() {
		return _size;
	}

private static:
	termios _origTermios;
	long[2] _size = [80, 24];
	long[2] _newSize = [long.max, long.max];
	string _buffer;

	void _enableRawMode() {
		if (tcgetattr(STDIN_FILENO, &_origTermios) == -1)
			die("tcgetattr");
		atexit(&destroy);
		termios raw = _origTermios;
		raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
		raw.c_oflag &= ~(OPOST);
		raw.c_cflag |= (CS8);
		raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
		raw.c_cc[VMIN] = 0;
		raw.c_cc[VTIME] = 1;
		if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1)
			die("tcsetattr");
		write("\x1b[?1049h"); // Switch to alternative screen
		flush();
	}

	extern (C) void _disableRawMode() {
		write("\x1b[?1049l"); // Switch to main screen
		flush();
		if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &_origTermios) == -1)
			die("tcsetattr");
	}

	extern (C) void _refreshSize(int) {
		Terminal.flush();
		winsize ws;
		if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == -1 || !ws.ws_col) {
			char[32] buf;
			size_t i;
			Terminal.write("\x1b[999C\x1b[999B");
			Terminal.write("\x1b[6n");
			Terminal.flush();
			while (i < buf.length) {
				buf[i] = cast(char)Terminal.read();
				if (buf[i] == 'R')
					break;
				i++;
			}

			if (buf[0 .. 2] != "\x1b[" || !sscanf(&buf[2], "%d;%d", &_newSize[1], &_newSize[0]))
				Terminal.die("_refreshSize");
		} else {
			_newSize[0] = ws.ws_col;
			_newSize[1] = ws.ws_row;
		}
	}
}

enum Color {
	defaultColor = 39,

	black = 30,
	red = 31,
	green = 32,
	yellow = 33,
	blue = 34,
	magenta = 35,
	cyan = 36,
	white = 37,

	brightBlack = 90,
	brightRed = 91,
	brightGreen = 92,
	brightYellow = 93,
	brightBlue = 94,
	brightMagenta = 95,
	brightCyan = 96,
	brightWhite = 97,
}

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
		import stdx.string : numberToString;

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
		import std.range;

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

struct Editor {
public:
	void open(string file) {
		import std.file : readText;
		import std.path : absolutePath;
		import std.string : splitLines;
		import std.array : array;
		import std.algorithm : map, each, copy;
		import core.memory : GC;

		_file = absolutePath(file);

		Terminal.moveTo(0, 0);
		Terminal.write("Loading ");
		Terminal.write(file);
		Terminal.write("...");
		Terminal.flush();

		string text = readText(file);

		auto lines = text.splitLines;

		size_t idx;

		_lines.length = lines.length;

		lines.map!((x) {
			Terminal.moveTo(0, 1);
			Terminal.write(format("Constructing %d/%d...", ++idx, lines.length));
			Terminal.flush();
			return x;
		})
			.map!(x => Line(UTFString(x)))
			.copy(_lines);

		Terminal.moveTo(0, 1);
		Terminal.write(format("Constructing %d/%d... [\x1b[32mDONE\x1b[0m]", idx, lines.length));
		Terminal.flush();

		GC.disable;

		scope (exit) {
			GC.enable();
			GC.collect();
		}

		idx = 0;
		_lines.each!((ref x) {
			Terminal.moveTo(0, 2);
			Terminal.write(format("Rendering %d/%d...", ++idx, _lines.length));
			Terminal.flush();
			x.refresh();
			GC.collect();
		});

		Terminal.moveTo(0, 2);
		Terminal.write(format("Rendering %d/%d... [\x1b[32mDONE\x1b[0m]", idx, lines.length));
		Terminal.flush();

		Line status;
		status.textParts.length = 1;
		status.textParts[0].str = UTFString(
				"Welcome to DE! | Ctrl+Q - Quit | Ctrl+W - Hide/Show line numbers | Ctrl+E Input command | Ctrl+R Save as | Ctrl+S Save |");
		status.textParts[0].style.bright = true;
		status.textParts[0].style.fg = Color.brightCyan;
		status.textParts[0].style.bg = Color.black;

		_addStatus(status);

		foreach (ref bool l; _refreshLines)
			l = true;

		drawRows();
	}

	void save(string file) {
		import std.algorithm : map, joiner;
		import std.range : chain;
		import std.conv : octal, to;
		import std.string : toStringz, fromStringz;
		import core.stdc.string : strerror;

		if (!file.length) {
			_addBadStatus("No file to save to!");
			return;
		}

		string buf = _lines.map!((ref Line l) => l.text.rawData).joiner("\n").to!string ~ "\n";
		scope (exit)
			buf.destroy;

		int fd = .open(file.toStringz, O_RDWR | O_CREAT, octal!644);
		if (fd == -1) {
			_addBadStatus(format("Could not save file: %s. Error: %s", file, strerror(errno).fromStringz));
			return;
		}
		scope (exit)
			close(fd);

		if (ftruncate(fd, cast(long)buf.length) == -1) {
			_addBadStatus(format("Could not save file: %s. Error: %s", file, strerror(errno).fromStringz));
			return;
		}
		if (write(fd, buf.ptr, cast(long)buf.length) != buf.length) {
			_addBadStatus(format("Could not save file: %s. Error: %s", file, strerror(errno).fromStringz));
			return;
		}

		{
			import core.memory : GC;
			import std.file : write;
			import std.format : format;

			with (GC.stats)
				write(file ~ ".stats", format("usedSize: %.1f KiB, freeSize: %.1f KiB\n", usedSize / 1024.0f, freeSize / 1024.0f));
		}
		_dirtyFactor = 0;
		_addGoodStatus(format("Saved to file: %s", file));
	}

	void drawRows() {
		auto screenHeight = Terminal.size[1] - _statusHeight;

		foreach (long y, refresh; _refreshLines) {
			if (!refresh)
				continue;
			long row = y + _scrollY;
			Terminal.moveTo(0, y);
			Terminal.write("\x1b[49m");
			Terminal.clearLine();
			if (_showLineNumber)
				Terminal.write(format("\x1b[%d;%dm %*d \x1b[0m", Color.white, Color.black + 10, _lineNumberWidth - 2, row + 1));

			if (row < 0 || row >= _lines.length) {
				Terminal.write("\x1b[90m~\x1b[0m");

				if (!_lines.length && row == screenHeight / 3) {
					import std.algorithm : min;

					string welcome = format("D editor -- version %s", Build.version_);
					size_t welcomeLength = min(welcome.length, Terminal.size[0]);
					long padding = cast(long)(Terminal.size[0] - welcomeLength) / 2;

					Terminal.moveTo(padding, y);
					Terminal.write("\x1b[1m");
					Terminal.write(welcome[0 .. welcomeLength]);
					Terminal.write("\x1b[0m");
				}
			} else {
				import std.algorithm : min;

				Line* l = &_lines[row];

				Terminal.write((*l)[_scrollX .. _scrollX + Terminal.size[0] - _lineNumberWidth]);
			}
		}
	}

	void refreshScreen() {
		import std.string : toStringz;
		import std.range : repeat;
		import std.array : array;
		import std.path : baseName;

		if (Terminal.gotResized) {
			import std.algorithm : each;

			_refreshLines.length = Terminal.size[1];
			_refreshLines.each!((ref x) => x = true);
		}

		static bool wasMessages = false;

		if (!!wasMessages != !!_statusMessages.length) {
			_refreshLines[Terminal.size[1] - 3] = true;
			_refreshLines[Terminal.size[1] - 2] = true;
		}

		wasMessages = !!_statusMessages.length;
		if (_statusMessages.length) {
			import std.range : popFront, front;

			if (MonoTime.currTime > _statusDecayAt) {
				_statusMessages.popFront;
				if (_statusMessages.length)
					_statusDecayAt = MonoTime.currTime + _statusMessages.front.duration;
				_refreshLines[Terminal.size[1] - 3] = true;
				_refreshLines[Terminal.size[1] - 2] = true;
			}
		}

		_statusHeight = (_showCommandInput || _statusMessages.length) ? 2 : 1;

		Terminal.cursorVisibility = false;

		if (_showLineNumber) {
			ulong newWidth;
			if (_lines.length) {
				import std.math : log10;
				import std.algorithm : min;

				newWidth = cast(long)log10(min(_scrollY + Terminal.size[1] - _statusHeight, _lines.length)) + 1;
			} else
				newWidth = 1;

			newWidth += 2;

			if (newWidth > _lineNumberWidth || !_lineNumberWidth)
				_lineNumberWidth = newWidth;
		} else
			_lineNumberWidth = 0;

		drawRows();

		foreach (ref bool l; _refreshLines)
			l = false;

		Terminal.moveTo(0, Terminal.size[1] - _statusHeight);
		Terminal.clearLine();

		string str = format("%s - %d lines %d/%d", _file.baseName, _lines.length, _row + 1, _lines.length);
		string dirty = format("dirty: %d", _dirtyFactor);

		// dfmt off
		Terminal.write(Line(UTFString(), [
			Line.Part(() { TextStyle t; t.bg = t.fg; t.fg = Color.black; return t; }(), UTFString(str)),
			Line.Part(() { TextStyle t; t.bg = t.fg; t.fg = Color.brightBlack; return t; }(), UTFString(" | ")),
			Line.Part(() { TextStyle t; t.bg = t.fg; t.fg = _dirtyFactor ? Color.red : Color.green; return t; }(), UTFString(dirty)),
			Line.Part(() { TextStyle t; t.bg = t.fg; t.fg = Color.black; return t; }(), UTFString()),
		], Line.RenderStyle.fillWidth), Terminal.size[0]);
		// dfmt on

		if (_showCommandInput) {
			Terminal.moveTo(0, Terminal.size[1] - _statusHeight + 1);
			Terminal.clearLine();
			Terminal.write(_commandLine);
		} else if (_statusMessages.length) {
			import std.range : front;

			Terminal.moveTo(0, Terminal.size[1] - _statusHeight + 1);
			Terminal.clearLine();
			_statusMessages.front.line.slice((const(char[]) str) { Terminal.write(str); }, 0, Terminal.size[0]);
		}

		Line* l = &_lines[_row];

		// This needs to be done render the cursor at the logical location
		// This makes sure that the cursor is not rendered in the middle of a tab, but rather it is rendered at the start
		// of that tab character.
		const long renderedCursorX = l.indexToColumn(_dataIdx);

		Terminal.moveTo(renderedCursorX + _lineNumberWidth - _scrollX, (_row - _scrollY));

		Terminal.cursorVisibility = true;
		Terminal.flush();
	}

	void addChar(dchar ch) {
		if (_row == _lines.length) {
			_lines ~= Line();
			if (_row >= _scrollY + Terminal.size[1])
				_scrollY++;
		}

		if (_dataIdx > _lines[_row].text.length)
			_dataIdx = _lines[_row].text.length;

		_lines[_row].addChar(_dataIdx, ch);
		_dataIdx++;
		_dirtyFactor++;

		_column = _lines[_row].indexToColumn(_dataIdx);

		_refreshLines[_row - _scrollY] = true;
	}

	enum RemoveDirection {
		left = -1,
		right = 0
	}

	void removeChar(RemoveDirection dir) {
		import std.algorithm : remove;

		if (_dataIdx > _lines[_row].text.length)
			_dataIdx = _lines[_row].text.length;

		if (dir == RemoveDirection.left && _dataIdx == 0) {
			if (_row <= 0)
				return;
			_dataIdx = _lines[_row - 1].text.length;
			_lines[_row - 1].text ~= _lines[_row].text;
			_lines = _lines.remove(_row);
			_row--;
			_lines[_row].refresh;
			_dirtyFactor++;
		} else if (dir == RemoveDirection.right && _dataIdx == _lines[_row].text.length) {
			if (_row >= _lines.length - 1)
				return;

			_lines[_row].text ~= _lines[_row + 1].text;
			_lines = _lines.remove(_row + 1);
			_lines[_row].refresh;
			_dirtyFactor++;
		} else {
			_lines[_row].removeChar(_dataIdx + dir);
			_dataIdx += dir;
			_dirtyFactor++;
		}
	}

	void newLine() {
		auto text = _lines[_row].text;

		if (_dataIdx > _lines[_row].text.length)
			_dataIdx = _lines[_row].text.length;

		_lines[_row].text = UTFString(text[0 .. _dataIdx]);
		_lines = _lines[0 .. _row + 1] ~ Line(UTFString(text[_dataIdx .. $])) ~ _lines[_row + 1 .. $];
		_lines[_row].refresh;
		_lines[_row + 1].refresh;
		_dataIdx = 0;
		_row++;

		_dirtyFactor++;
	}

	bool getStringInput(string question, ref string answer) {
		bool oldSCI = _showCommandInput;
		scope (exit) {
			_showCommandInput = oldSCI;
			_refreshLines[Terminal.size[1] - 2] = true;
			_refreshLines[Terminal.size[1] - 1] = true;
			refreshScreen();
		}
		_showCommandInput = true;
		_commandLine.textParts.length = 2;
		_commandLine.textParts[0] = Line.Part(() { TextStyle t; t.fg = Color.cyan; return t; }(), UTFString(question ~ ": "));
		_commandLine.textParts[1] = Line.Part(() { TextStyle t; t.fg = Color.white; return t; }(), UTFString(answer));

		long idx = answer.length;
		while (true) {
			_refreshLines[Terminal.size[1] - 2] = true;
			_refreshLines[Terminal.size[1] - 1] = true;
			refreshScreen();
			Terminal.moveTo(idx + question.length + 2, Terminal.size[1] - 1);
			Terminal.flush();

			Key k = Terminal.read();

			if (k == Key.unknown)
				continue;
			switch (k) {
			case Key.return_:
				answer = _commandLine.textParts[1].str.rawData.idup;
				return true;
			case Key.arrowLeft:
				if (idx > 0)
					idx--;
				break;
			case Key.arrowRight:
				if (idx < answer.length)
					idx++;
				break;

			case CTRL_KEY('q'):
			case Key.escape:
				return false;

			case Key.delete_:
			case Key.backspace:
			case CTRL_KEY('h'):
				auto dir = k == Key.backspace ? RemoveDirection.left : RemoveDirection.right;
				if (dir == RemoveDirection.right || idx > 0) {
					idx += dir;
					_commandLine.textParts[1].str.remove(idx);
				}
				break;

			default:
				if (k.isTextChar && k <= Key.lettersEnd) {
					import std.utf : encode;

					char[4] buf;
					auto len = encode(buf, cast(dchar)k);
					_commandLine.textParts[1].str.insert(idx, buf[0 .. len]);
					idx++;
				}
				break;
			}
		}
	}

	bool processKeypress() {
		import std.algorithm : min, max;
		import std.uni : graphemeStride;
		import std.algorithm : each;

		static size_t quitTimes = 4;

		long screenHeight = Terminal.size[1] - _statusHeight;

		alias updateScreen = () { _refreshLines.each!((ref x) => x = true); };

		void applyScroll() {
			if (_row < _scrollY)
				_scrollY = _row;
			else if (_row >= _scrollY + screenHeight)
				_scrollY = (_row - screenHeight) + 1;

			if (_column < _scrollX)
				_scrollX = _column;
			else if (_column >= (Terminal.size[0] - _lineNumberWidth) + _scrollX)
				_scrollX = _column - (Terminal.size[0] - _lineNumberWidth) + 1;
			updateScreen();
		}

		Key k = Terminal.read();
		if (k == Key.unknown)
			return true;
		switch (k) {
		default:
			if (k.isTextChar && k <= Key.lettersEnd)
				addChar(cast(dchar)k);
			break;

		case Key.return_:
			newLine();
			applyScroll();
			break;

		case CTRL_KEY('h'):
		case Key.backspace:
			removeChar(RemoveDirection.left);
			applyScroll();
			break;

		case Key.delete_:
			removeChar(RemoveDirection.right);
			applyScroll();
			break;

		case CTRL_KEY('l'):
			applyScroll();
			break;

		case Key.escape:
			// This disallow the user to write escapes codes into the file by pressing escape
			break;

		case CTRL_KEY('q'):
			if (_dirtyFactor && quitTimes > 0) {
				_addBadStatus(format("WARNING!!! File has unsaved changes. Press Ctrl-Q %d more times to quit.", quitTimes));
				quitTimes--;
				return true;
			} else
				return false;
		case CTRL_KEY('w'):
			_showLineNumber = !_showLineNumber;
			refreshScreen();
			break;
		case CTRL_KEY('e'):
			_showCommandInput = !_showCommandInput;
			_refreshLines[Terminal.size[1] - 3] = true;
			_refreshLines[Terminal.size[1] - 2] = true;
			break;

		case CTRL_KEY('r'):
		case CTRL_KEY('s'):
			if (!_file || k == CTRL_KEY('r')) {
				import std.file : getcwd;
				import std.path : absolutePath;

				if (!_file)
					_file = getcwd() ~ "/";
				if (!getStringInput("Filepath", _file))
					break;

				_file = absolutePath(_file);
			}
			save(_file);
			break;

		case Key.arrowUp:
			if (_row > 0) {
				_row--;
				_dataIdx = _lines[_row].columnToIndex(_column);
				applyScroll();
			}
			break;
		case Key.arrowDown:
			if (_row < _lines.length - 1) {
				_row++;
				_dataIdx = _lines[_row].columnToIndex(_column);
				applyScroll();
			}
			break;
		case Key.arrowLeft:
			if (_dataIdx > _lines[_row].text.length)
				_dataIdx = _lines[_row].text.length;
			else if (_dataIdx > 0)
				_dataIdx--;
			else if (_row > 0) {
				_row--;
				_dataIdx = cast(long)_lines[_row].text.length;
			}

			_column = _lines[_row].indexToColumn(_dataIdx);
			applyScroll();
			break;
		case Key.arrowRight:
			if (_dataIdx < _lines[_row].text.length)
				_dataIdx++;
			else if (_row < _lines.length - 1) {
				_row++;
				_dataIdx = 0;
			}

			_column = _lines[_row].indexToColumn(_dataIdx);
			applyScroll();
			break;

		case Key.home:
			_dataIdx = 0;

			_column = _lines[_row].indexToColumn(_dataIdx);
			applyScroll();
			break;
		case Key.end:
			_dataIdx = cast(long)_lines[_row].text.length;

			_column = _lines[_row].indexToColumn(_dataIdx);
			applyScroll();
			break;

			//TODO: move offset not cursor?
		case Key.pageUp:
			_row = max(0L, _scrollY - screenHeight);
			applyScroll();
			break;
		case Key.pageDown:
			_row = min(_lines.length - 1, _scrollY + screenHeight * 2 - 1);
			applyScroll();
			break;
		}

		quitTimes = 4;
		return true;
	}

private:
	string _file;
	size_t _dirtyFactor;

	long _dataIdx; // data location
	long _column, _row; // _column will be the screen location
	long _scrollX, _scrollY;
	Line[] _lines;

	bool _showLineNumber = true;
	ulong _lineNumberWidth = 5;

	bool _showCommandInput = false;
	Line _commandLine;
	ulong _statusHeight = 1;

	bool[] _refreshLines;

	struct Status {
		Line line;
		Duration duration;
	}

	Status[] _statusMessages;
	MonoTime _statusDecayAt;

	void _addStatus(Line status, Duration duration = 1.seconds) {
		if (!_statusMessages.length)
			_statusDecayAt = MonoTime.currTime + duration;
		_statusMessages ~= Status(status, duration);
	}

	void _addGoodStatus(string str) {
		Line status;
		status.textParts.length = 1;
		status.textParts[0].str = UTFString(str);
		status.textParts[0].style.underscore = true;
		status.textParts[0].style.fg = Color.green;
		status.textParts[0].style.bg = Color.black;
		_addStatus(status);
	}

	void _addBadStatus(string str) {
		Line status;
		status.textParts.length = 1;
		status.textParts[0].str = UTFString(str);
		status.textParts[0].style.underscore = true;
		status.textParts[0].style.fg = Color.black;
		status.textParts[0].style.bg = Color.red;
		_addStatus(status);
	}
}

version (unittest) {

} else {
	void main(string[] args) {
		Terminal.init();
		scope (exit)
			Terminal.destroy;
		Editor editor;
		scope (exit)
			editor.destroy;

		editor.open(args.length > 1 ? args[1] : "testfile.txt");

		while (true) {
			editor.refreshScreen();
			if (!editor.processKeypress())
				break;

			//import core.memory : GC;

			//GC.collect();
		}
	}
}

/*@("Test load file")
unittest {
	Terminal.init();
	scope (exit)
		Terminal.destroy;
	Editor editor;
	scope (exit)
		editor.destroy;

	editor.open("testfile.txt");
	import std.stdio;

	stderr.writeln("Editor has loaded");
	assert(0, "derp");
}*/
