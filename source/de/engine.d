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

		_pmFront = new PixelMap();
		_pmFront.data = new Color[_width * _height];
		_pmFront.width = _width;
		_pmFront.height = _height;

		_pmBack = new PixelMap();
		_pmBack.data = new Color[_width * _height];
		_pmBack.width = _width;
		_pmBack.height = _height;

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

				foreach (ref Color c; _pmFront.data)
					c = Color(0, 0, 0, 0);

				Color bg = Color(0, 0, 0, 255);
				outer_loop: foreach (Line* line; _textBuffer.lines)
					foreach (part; line.parts)
						if (TextPart* _ = part.peek!TextPart) {
							bg = _.bg;
							break outer_loop;
						}
				foreach (ref Color c; _pmBack.data)
					c = bg;

				int counter = 0;
				long y = 0;
				foreach (Line* line; _textBuffer.lines) {
					long x = 0;
					Vec2!ulong size = line.getSize(_ft);

					foreach (part; line.parts) {
						if (TextPart* _ = part.peek!TextPart) {
							long myX = _.getSize(_ft).x;
							for (long yy = y; yy < y + size.y && yy < _pmBack.height; yy++)
								for (long xx = x; xx < x + myX; xx++)
									_pmBack.data[yy * _pmBack.width + xx] = _.bg;
							x += myX;
						}
					}

					x = 0;

					foreach (part; line.parts) {
						if (TextPart* _ = part.peek!TextPart) {
							_ft.render(_pmFront, *_, x, y + size.y);
							x += _.getSize(_ft).x;
						} else
							assert(0, "TODO: implement");
					}
					y += size.y;
					if (y >= _pmFront.height)
						break;
				}

				foreach (idx, const ref Color c; _pmFront.data)
					_pmBack.data[idx] = mix(_pmBack.data[idx], c, c.a);

				_platform.display(_pmBack);
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

		_pmFront.data.destroy;
		_pmFront.data = new Color[_width * _height];
		_pmFront.width = _width;
		_pmFront.height = _height;

		_pmBack.data.destroy;
		_pmBack.data = new Color[_width * _height];
		_pmBack.width = _width;
		_pmBack.height = _height;
	}

private:
	IPlatform _platform;
	PixelMap _pmFront; // Text
	PixelMap _pmBack; // Background
	FreeType _ft;
	bool _quit = false;
	size_t _width, _height;
	bool _wantRedraw;

	TextBuffer _textBuffer;
}
