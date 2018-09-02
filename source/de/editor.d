module de.editor;

import de.terminal : Terminal, Key, Color;
import de.line : Line, TextStyle;
import de.utfstring : UTFString;
import de.build : Build, Config;

import std.format : format;

import core.sys.posix.unistd;
import core.sys.posix.fcntl;
import core.stdc.errno;
import core.time : Duration, MonoTime, seconds;

bool isTextChar(Key k) {
	import std.uni : isControl;

	return !isControl(cast(dchar)k);
}

alias CTRL_KEY = (char k) => cast(Key)((k) & 0x1f);

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
			if (_showLineNumber) {
				import de.line : TextStyle;

				TextStyle number, line;
				number.bright = true;
				line.dim = true;
				Terminal.write(format("%s %*d \x1b[0m%s%c\x1b[0m ", number, _lineNumberWidth - _lineNumberDesignWidth, row + 1, line, Config.lineNumberSeparator));
			}

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
			import std.algorithm : min, max;

			ulong newWidth;
			if (_lines.length) {
				import std.math : log10;

				newWidth = cast(long)log10(min(_scrollY + Terminal.size[1] - _statusHeight, _lines.length)) + 1;
			} else
				newWidth = 1;

			newWidth += _lineNumberDesignWidth;
			newWidth = newWidth.max(_lineNumberMinWidth + _lineNumberDesignWidth);

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
			Line.Part(() { TextStyle t; t.bg = t.fg; t.fg = Color.brightBlack; return t; }(), UTFString(" │ ")),
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

			if (_dataIdx > 0)
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
	enum ulong _lineNumberMinWidth = 3;
	enum ulong _lineNumberDesignWidth = 4;

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
