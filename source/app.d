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

enum Key : int {
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
		printf("\x1b[1mThank you for using DE - Powered by https://dlang.org/\n\x1b[0m");
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

	void moveTo(int x = 0, int y = 0) {
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

	@property int[2] size() {
		return _size;
	}

private static:
	termios _origTermios;
	int[2] _size = [80, 24];
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
			/*char[32] buf;
			size_t i;
			Terminal.write("\x1b[999C\x1b[999B");
			Terminal.write("\x1b[6n");
			Terminal.flush();
			while (i < buf.length) {
				buf[i] = Terminal.read();
				if (buf[i] == 'R')
					break;
				i++;
			}

			if (buf[0 .. 2] != "\x1b[" || !sscanf(&buf[2], "%d;%d", &_size[1], &_size[0]))*/
			Terminal.die("_refreshSize");
		} else {
			_size[0] = ws.ws_col;
			_size[1] = ws.ws_row;
		}
	}
}

struct Line {
	string _text;
	string text;

	this(string text_) {
		import std.regex : replaceAll, regex;

		if (text_.length)
			_text = text_;
		text = _text.replaceAll(regex(r"\t"), "  ");
	}

	@property size_t length() {
		return text.length;
	}
}

struct Editor {
public:
	void open(string file = __FILE_FULL_PATH__) {
		import std.file : readText;
		import std.string : splitLines;
		import std.array : array;
		import std.algorithm : map;

		string text = readText(file);
		_lines = text.splitLines.map!(x => Line(x)).array;
	}

	void drawRows() {
		foreach (int y; 0 .. Terminal.size[1]) {
			int row = y + _offsetY;
			Terminal.moveTo(0, y);
			Terminal.clearLine();
			if (_showLineNumber)
				Terminal.write(format("\x1b[90m%*d| \x1b[0m", _lineNumberWidth - 2, row));

			if (row >= _lines.length && row > 0) {
				Terminal.write("\x1b[90m~\x1b[0m");

				if (!_lines.length && row == Terminal.size[1] / 3) {
					import std.algorithm : min;

					string welcome = format("D editor -- version %s LastKey: %s (%c)", Build.version_, _lastKey, cast(char)_lastKey);
					size_t welcomeLength = min(welcome.length, Terminal.size[0]);
					int padding = cast(int)(Terminal.size[0] - welcomeLength) / 2;

					Terminal.moveTo(padding, y);
					Terminal.write("\x1b[1m");
					Terminal.write(welcome[0 .. welcomeLength]);
					Terminal.write("\x1b[0m");
				}
			} else {
				import std.algorithm : min;

				Line* l = &_lines[row];

				long len = min(cast(long)l.length - _offsetX, Terminal.size[0] - _lineNumberWidth);

				if (len > 0)
					Terminal.write(l.text[_offsetX .. _offsetX + len]);
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

				_lineNumberWidth = cast(int)log10(min(_offsetY + Terminal.size[1] - 1, _lines.length - 1)) + 1;
			} else
				_lineNumberWidth = 1;

			_lineNumberWidth += 2;
		} else
			_lineNumberWidth = 0;
		drawRows();
		Terminal.moveTo(_cursorX + _lineNumberWidth - _offsetX, (_cursorY - _offsetY));
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
			if (_cursorY > 0)
				_cursorY--;
			break;
		case Key.arrowDown:
			if (_cursorY < _lines.length - 1)
				_cursorY++;
			break;
		case Key.arrowLeft:
			if (_cursorX > 0)
				_cursorX--;
			else if (_cursorY > 0) {
				_cursorY--;
				_cursorX = cast(int)_lines[_cursorY].length;
			}
			break;
		case Key.arrowRight:
			if (_cursorX < _lines[_cursorY].length)
				_cursorX++;
			else if (_cursorY < _lines.length - 1) {
				_cursorY++;
				_cursorX = 0;
			}
			break;

		case Key.home:
			_cursorX = 0;
			break;
		case Key.end:
			_cursorX = cast(int)_lines[_cursorY].length;
			break;
		case Key.pageUp:
			_cursorY = max(0, _cursorY - Terminal.size[1]);
			break;
		case Key.pageDown:
			_cursorY = min(_lines.length - 1, _cursorY + Terminal.size[1]);
			break;
		default:
			break;
		}

		if (_cursorY < _offsetY)
			_offsetY = _cursorY;
		if (_cursorY >= _offsetY + Terminal.size[1])
			_offsetY = (_cursorY - Terminal.size[1]) + 1;

		if (_cursorX < _offsetX)
			_offsetX = _cursorX;
		if (_cursorX >= (Terminal.size[0] - _lineNumberWidth) + _offsetX)
			_offsetX = _cursorX - (Terminal.size[0] - _lineNumberWidth) + 1;

		return true;
	}

private:
	int _cursorX, _cursorY;
	int _offsetX, _offsetY;
	Key _lastKey;
	Line[] _lines;

	bool _showLineNumber = true;
	uint _lineNumberWidth = 5;
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
