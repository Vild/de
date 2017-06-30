module de.engine;

import de.platform;
import de.config;
import de.pixelmap;
import de.textrenderer;
import de.textbuffer;
import de.container;

import std.math;
import core.thread;
import std.datetime;
import std.stdio;

class Engine {
public:
	this() {
		_width = 1280;
		_height = 720;
		_platform = new CurrentPlatform("DE", _width, _height);

		_pm = new PixelMap();
		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;

		_ft = new FreeType(FONT);

		_textBuffer = new TextBuffer();
	}

	~this() {
		_platform.destroy;
	}

	void loadFile(string path) {
		import std.stdio : File;
		import std.algorithm : each;
		import std.conv : to;

		_textBuffer.clear();

		File file = File(path);
		import std.math : sqrt;

		file.byLine().each!(l => _textBuffer.addLine(size_t.max, l.to!dstring, 32));
	}

	int run() {
		immutable Color[16] colors = [Color(0, 0, 0, 255), Color(0, 0, 170, 255), Color(0, 170, 0, 255), Color(0, 170, 170,
				255), Color(170, 0, 0, 255), Color(170, 0, 170, 255), Color(170, 85, 0, 255), Color(170, 170, 170, 255),
			Color(85, 85, 85, 255), Color(85, 85, 255, 255), Color(85, 255, 85, 255), Color(85, 255, 255, 255), Color(255,
					85, 85, 255), Color(255, 85, 255, 255), Color(255, 255, 85, 255), Color(255, 255, 255, 255)];

		_wantRedraw = true;
		while (!_quit) {
			_platform.update(this);
			if (_wantRedraw || _platform.wantRedisplay) {
				//TODO: make better
				foreach (ref Color c; _pm.data)
					c = Color(0, 0, 0, 255);

				int counter = 0;
				long y = 0;
				foreach (Line* line; _textBuffer.lines) {
					long x = 0;
					Vec2!ulong size = line.getSize(_ft);

					foreach (part; line.parts) {
						if (TextPart* _ = part.peek!TextPart) {
							long myX = _.getSize(_ft).x;
							for (long yy = y; yy < y + size.y && yy < _pm.height; yy++)
								for (long xx = x; xx < x + myX; xx++)
									_pm.data[yy * _pm.width + xx] = _.bg;
							x += myX;
						}
					}

					x = 0;

					foreach (part; line.parts) {
						if (TextPart* _ = part.peek!TextPart) {
							_ft.render(_pm, *_, x, y + size.y);
							x += _.getSize(_ft).x;
						} else
							assert(0, "TODO: implement");
					}
					y += size.y;
					if (y >= _pm.height)
						break;
				}

				_platform.display(_pm);
				_wantRedraw = false;
			} else
				Thread.sleep(10.msecs);
		}
		return 0;
	}

	void quit() {
		_quit = true;
	}

	void resize(size_t width, size_t height) {
		_width = width;
		_height = height;

		_pm.data.destroy;
		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;
	}

private:
	IPlatform _platform;
	PixelMap _pm;
	FreeType _ft;
	bool _quit = false;
	size_t _width, _height;
	bool _wantRedraw;

	TextBuffer _textBuffer;
}
