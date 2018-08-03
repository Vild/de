import core.sys.posix.unistd;
import core.sys.posix.termios;
import core.sys.posix.sys.ioctl;
import core.sys.posix.signal;

import core.stdc.ctype;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.errno;

import std.format : format;

import linebreak;

alias CTRL_KEY = (char k) => cast(Key)((k) & 0x1f);

static struct Build {
static:
	enum string version_ = "0.0.1";
}

static struct Config {
static:
	size_t tabSize = 2;
}

enum Key : long {
	unknown = 0,

	arrowUp = 1000,
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

		_enableRawMode();
		_refreshSize(0);
	}

	extern (C) void destroy() {
		static bool called;
		if (called)
			return;
		called = true;
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

	void write(string str) {
		_buffer ~= str;
	}

	void flush() {
		import std.string : toStringz;

		.write(STDOUT_FILENO, _buffer.toStringz, _buffer.length);
		_buffer.length = 0;
	}

	Key read() {
		char readCh() {
			long nread;

			char c = '\0';
			static if (false) {
				while ((nread = .read(STDIN_FILENO, &c, 1)) != 1) {
					if (nread == -1 && errno != EAGAIN && errno != EINTR)
						Terminal.die("read");
				}
			} else if (.read(STDIN_FILENO, &c, 1) == -1 && errno != EAGAIN && errno != EINTR)
				Terminal.die("read");
			return c;
		}

		Key actionKeys(char c) {
			if (readCh() != '~')
				Terminal.die("read - expected '~'");
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

		char c = readCh();
		if (c == '\x1b') {
			if (readCh() == '[') {
				switch (c = readCh()) {
				case '0': .. case '9':
					return actionKeys(c);
				case 'A': .. case 'D':
				case 'H':
				case 'F':
					return arrowKeys(c);
				default:
					return Key.unknown;
				}

			} else if (c == 'O') {
				return arrowKeys(readCh());
			} else
				Terminal.die("read - expected '['");
		}
		return cast(Key)c;
	}

	void moveTo(long x = 0, long y = 0) {
		write(format("\x1b[%d;%dH", y + 1, x + 1));
	}

	void clear() {
		write("\x1b[2J");
	}

	void clearLine() {
		write("\x1b[K");
	}

	@property void cursorVisibility(bool v) {
		write("\x1b[?25" ~ (v ? "h" : "l"));
	}

	@property long[2] size() {
		return _size;
	}

private static:
	termios _origTermios;
	long[2] _size = [80, 24];
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

			if (buf[0 .. 2] != "\x1b[" || !sscanf(&buf[2], "%d;%d", &_size[1], &_size[0]))
				Terminal.die("_refreshSize");
		} else {
			_size[0] = ws.ws_col;
			_size[1] = ws.ws_row;
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

	Color fg = Color.defaultColor;
	Color bg = Color.defaultColor; // + 10

	string toString() {
		import std.array : appender;
		import std.conv : to;

		auto str = appender!string();
		str.reserve = 3 + 8 * 2 + (3 + 1) * 2;

		str ~= "\x1b[";
		if (bright)
			str ~= "1;";
		if (dim)
			str ~= "2;";
		if (italic)
			str ~= "3;";
		if (underscore)
			str ~= "4;";
		if (blink)
			str ~= "5;";
		if (reverse)
			str ~= "7;";
		if (crossedOut)
			str ~= "9;";
		if (overscore)
			str ~= "53;";

		str.put((cast(int)fg).to!string);
		str ~= ";";
		str.put((cast(int)bg + 10).to!string);
		str ~= "m";
		return str.data;
	}
}

struct Line {
	struct Part {
		TextStyle style;
		string str;

		@property size_t length() {
			return str.length;
		}

		size_t opDollar(size_t pos : 0)() {
			return length;
		}

		string opSlice(size_t x, size_t y) {
			assert(x < y, format!"%d < %d"(x, y));
			assert(x <= str.length, format!"(y=%d), x=%d is outside of string(len: %d)"(y, x, str.length));
			assert(y <= str.length, format!"(x=%d), y=%d is outside of string(len: %d)"(x, y, str.length));
			return style.toString() ~ str[x .. y] ~ "\x1b[0m";
		}

		string toString() {
			return opSlice(0, length);
		}
	}

	string text;
	Part[] textParts;

	string toString() {
		return opSlice(0, length);
	}

	@property size_t length() {
		import std.algorithm : map, sum;

		return textParts.map!"a.length".sum;
	}

	size_t opDollar(size_t pos : 0)() {
		return length;
	}

	string opSlice(size_t x, size_t y) {
		import std.range;
		import std.array : appender;

		auto output = appender!string;
		Part[] parts = textParts;

		if (parts.empty || x == y)
			return "";

		// Step 1. discard parts until x is a valid location in part
		while (!parts.empty && x && x < y && x > parts[0].length) {
			x -= parts[0].length;
			y -= parts[0].length;
			parts.popFront;
		}

		if (parts.empty)
			return "";

		// Step 2 Get data so X becomes 0
		if (!parts.empty && x) {
			Part part = parts.front;
			parts.popFront;

			size_t sizeWant = y - x;
			if (part.length - x < sizeWant) // Won't find all the requested data in this part
				sizeWant = part.length - x;

			output ~= part[x .. sizeWant + x];
			x = 0;
			y -= sizeWant;
		}

		if (parts.empty)
			return output.data;

		// Step 3 Continue to get data until y = 0
		while (!parts.empty && y) {
			Part part = parts.front;
			parts.popFront;

			size_t sizeWant = y;
			if (part.length < sizeWant) // Won't find all the requested data in this part
				sizeWant = part.length;

			output ~= part[x .. sizeWant];

			y -= sizeWant;
		}

		return output.data;
	}

	bool haveRefreshed; //TODO:
	void refresh() {
		haveRefreshed = true;
		import std.string : indexOf;
		import std.algorithm : filter, sum;

		textParts.length = 0;
		size_t idx = 0;
		bool wasSpace;
		bool wasChar;
		foreach (ch; text) {
			Part part;
			if (ch == '\t') {
				import std.array : insertInPlace;
				import std.range : repeat;

				const size_t numberOfSpaces = (Config.tabSize) - (idx % Config.tabSize);
				part.str = format!"↦%*s"(numberOfSpaces - 1, "");
				part.style.fg = Color.brightBlack;

				wasSpace = false;
				wasChar = false;
				idx += numberOfSpaces;
			} else if (ch == ' ' && (!wasChar || (wasChar && textParts[$ - 1].str.length > 1
					&& textParts[$ - 1].str[$ - 2] == '/' && (textParts[$ - 1].str[$ - 1] == '/' || textParts[$ - 1].str[$ - 1] == '*')))) {
				if (wasSpace) {
					textParts[$ - 1].str ~= "⬩";
					idx++;
					continue;
				} else {
					part.str = "⬩";
					part.style.fg = Color.brightBlack;

					wasSpace = true;
					wasChar = false;

					idx++;
				}
			} else {
				if (wasChar) {
					textParts[$ - 1].str ~= format!"%c"(ch);
					idx++;
					continue;
				} else {
					part.str = format!"%c"(ch);
					wasSpace = false;
					wasChar = true;

					idx++;
				}
			}
			textParts ~= part;
		}
	}

	long indexToColumn(long dataIdx) {
		import std.algorithm : min;

		size_t idx = 0;
		foreach (ch; text[0 .. dataIdx.min(text.length)]) {
			if (ch == '\t')
				idx += (Config.tabSize - 1) - (idx % Config.tabSize);
			idx++;
		}
		return idx;
	}

	long columnToIndex(long column) {
		import std.algorithm : min;

		if (!column)
			return 0;

		size_t idx = 0;
		foreach (i, ch; text) {
			if (ch == '\t')
				idx += (Config.tabSize - 1) - (idx % Config.tabSize);
			idx++;
			if (column == idx)
				return i + 1;
			else if (column < idx)
				return i;
		}
		return column;
	}
}

struct Editor {
public:
	void open(string file = __FILE_FULL_PATH__) {
		import std.file : readText;
		import std.string : splitLines;
		import std.array : array;
		import std.algorithm : map, each;

		Terminal.moveTo(0, 0);
		Terminal.write("Loading ");
		Terminal.write(file);
		Terminal.write("...");
		Terminal.flush();

		string text = readText(file);
		_lines = text.splitLines.map!(x => Line(x)).array;
	}

	void drawRows() {
		foreach (long y; 0 .. Terminal.size[1]) {
			long row = y + _scrollY;
			Terminal.moveTo(0, y);
			Terminal.write("\x1b[49m");
			Terminal.clearLine();
			if (_showLineNumber)
				Terminal.write(format("\x1b[90m%*d| \x1b[0m", _lineNumberWidth - 2, row));

			if (row >= _lines.length && row > 0) {
				Terminal.write("\x1b[90m~\x1b[0m");

				if (!_lines.length && row == Terminal.size[1] / 3) {
					import std.algorithm : min;

					string welcome = format("D editor -- version %s LastKey: %s (%c)", Build.version_, _lastKey, cast(char)_lastKey);
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

				if (!l.haveRefreshed)
					l.refresh();
				Terminal.write((*l)[_scrollX .. _scrollX + Terminal.size[0] - _lineNumberWidth]);
			}
		}
	}

	void refreshScreen() {
		import std.string : toStringz;

		Terminal.cursorVisibility = false;

		if (_showLineNumber) {
			if (_lines.length) {
				import std.math : log10;
				import std.algorithm : min;

				_lineNumberWidth = cast(long)log10(min(_scrollY + Terminal.size[1] - 1, _lines.length - 1)) + 1;
			} else
				_lineNumberWidth = 1;

			_lineNumberWidth += 2;
		} else
			_lineNumberWidth = 0;
		drawRows();

		Line* l = &_lines[_row];

		// This needs to be done render the cursor at the logical location
		// This makes sure that the cursor is not rendered in the middle of a tab, but rather it is rendered at the start
		// of that tab character.
		const long renderedCursorX = l.indexToColumn(_dataIdx);

		Terminal.moveTo(renderedCursorX + _lineNumberWidth - _scrollX, (_row - _scrollY));

		Terminal.cursorVisibility = true;
		Terminal.flush();
	}

	bool processKeypress() {
		import std.algorithm : min, max;

		Key k = Terminal.read();
		if (k != Key.unknown)
			_lastKey = k;
		switch (k) {
		case CTRL_KEY('q'):
			return false;
		case CTRL_KEY('w'):
			_showLineNumber = !_showLineNumber;
			break;

		case Key.arrowUp:
			if (_row > 0) {
				_row--;
				_dataIdx = _lines[_row].columnToIndex(_column);
			}
			break;
		case Key.arrowDown:
			if (_row < _lines.length - 1) {
				_row++;
				_dataIdx = _lines[_row].columnToIndex(_column);
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
			break;
		case Key.arrowRight:
			if (_dataIdx < _lines[_row].text.length)
				_dataIdx++;
			else if (_row < _lines.length - 1) {
				_row++;
				_dataIdx = 0;
			}

			_column = _lines[_row].indexToColumn(_dataIdx);
			break;

		case Key.home:
			_dataIdx = 0;

			_column = _lines[_row].indexToColumn(_dataIdx);
			break;
		case Key.end:
			_dataIdx = cast(long)_lines[_row].text.length;

			_column = _lines[_row].indexToColumn(_dataIdx);
			break;

			//TODO: move offset not cursor?
		case Key.pageUp:
			_row = max(0, _scrollY - Terminal.size[1]);
			break;
		case Key.pageDown:
			_row = min(_lines.length - 1, _scrollY + Terminal.size[1] * 2 - 1);
			break;
		default:
			break;
		}

		if (_row < _scrollY)
			_scrollY = _row;
		else if (_row >= _scrollY + Terminal.size[1])
			_scrollY = (_row - Terminal.size[1]) + 1;

		if (_column < _scrollX)
			_scrollX = _column;
		else if (_column >= (Terminal.size[0] - _lineNumberWidth) + _scrollX)
			_scrollX = _column - (Terminal.size[0] - _lineNumberWidth) + 1;

		return true;
	}

private:
	long _dataIdx; // data location
	long _column, _row; // _column will be the screen location
	long _scrollX, _scrollY;
	Key _lastKey;
	Line[] _lines;

	bool _showLineNumber = true;
	ulong _lineNumberWidth = 5;
}

Editor* editor;

void main() {
	Terminal.init();
	scope (exit)
		Terminal.destroy;
	Editor editor;
	scope (exit)
		editor.destroy;

	editor.open();

	while (true) {
		editor.refreshScreen();
		if (!editor.processKeypress())
			break;
	}

}
