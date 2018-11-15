module de.terminal;

import core.sys.posix.unistd;
import core.sys.posix.termios;
import core.sys.posix.sys.ioctl;
import core.sys.posix.signal;
import core.sys.posix.fcntl;

import core.stdc.ctype;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.errno;

import std.traits : isNumeric;

import de.utfstring : numberToString;
import de.line : Line, TextStyle;

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

	arrowCtrlUp,
	arrowCtrlDown,
	arrowCtrlLeft,
	arrowCtrlRight,

	delete_,
	home,
	end,
	pageUp,
	pageDown,

	shiftTab
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
		static char[64 * 8] buffer;
		_buffer ~= numberToString(buffer, num, 10);
	}

	void flush() {
		import std.string : toStringz;

		.write(STDOUT_FILENO, _buffer.toStringz, _buffer.length);
		_buffer.length = 0;
	}

	Key read() {
		static dchar[] unprocessChars;
		dchar readCh() {
			import std.utf;
			import std.typecons;

			if (unprocessChars.length) {
				dchar ret = unprocessChars[0];
				unprocessChars = unprocessChars[1 .. $];
				return ret;
			}

			static char[] makeDchar;

			char[1] buf; // TODO: research if this could be like 8, without blocking a lot
			auto len = .read(STDIN_FILENO, buf.ptr, buf.length);
			if (len == -1 && errno != EAGAIN && errno != EINTR)
				Terminal.die("read");

			if (len > 0)
				foreach (ch; buf[0 .. len])
					makeDchar ~= ch;

			if (makeDchar.length && makeDchar.length >= makeDchar.stride())
				return makeDchar.decodeFront!(Yes.useReplacementDchar);
			else
				return Key.unknown;
		}

		Key actionKeys(dchar c) {
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

		Key arrowKeys(dchar c) {
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

		dchar c = readCh();
		if (c == '\x1b') {
			dchar seq0 = readCh();
			if (seq0 == '\0')
				return cast(Key)c;
			dchar seq1 = readCh();
			if (seq1 == '\0') {
				unprocessChars ~= seq1;
				return cast(Key)c;
			}

			dchar seq2 = '\0';
			dchar seq3 = '\0';
			dchar seq4 = '\0';
			if (seq0 == '[') {
				switch (seq1) {
				case '0': .. case '9':
					seq2 = readCh();
					if (seq2 == '~')
						return actionKeys(seq1);
					else if (seq1 == '1' && seq2 == ';') {
						seq3 = readCh();
						seq4 = readCh();
						if (seq3 != '5')
							break;
						switch (seq4) {
						case 'A':
							return Key.arrowCtrlUp;
						case 'B':
							return Key.arrowCtrlDown;
						case 'C':
							return Key.arrowCtrlRight;
						case 'D':
							return Key.arrowCtrlLeft;

						default:
							break;
						}
					} else
						break;
				case 'A': .. case 'D':
				case 'H':
				case 'F':
					return arrowKeys(seq1);
				case 'Z':
					return Key.shiftTab;
				default:
					break;
				}
			} else if (seq0 == 'O') {
				return arrowKeys(seq1);
			}

			unprocessChars ~= seq0;
			unprocessChars ~= seq1;
			if (seq2 != '\0')
				unprocessChars ~= seq2;
			if (seq3 != '\0')
				unprocessChars ~= seq3;
			if (seq4 != '\0')
				unprocessChars ~= seq4;
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
