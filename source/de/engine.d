module de.engine;

import de.platform;
import de.config;
import de.pixelmap;
import de.textrenderer;
import de.textbuffer;

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

		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;

		ft = new FreeType(FONT);

		textBuffer = new TextBuffer();
		textBuffer.addLine(0, "HelloWebFreak1", 32);
		textBuffer.addLine(2, "HelloWebFreak2", 32);
		textBuffer.addLine(0, "HelloWebFreak3", 32);
		textBuffer.addLine(3, "HelloWebFreak4", 32);
		textBuffer.addLine(1, "HelloWebFreak5", 32);
	}

	~this() {
		_platform.destroy;
	}

	int run() {
		_wantRedraw = true;
		while (!_quit) {
			_platform.update(this);
			if (_wantRedraw || _platform.wantRedisplay) {
				//TODO: make better
				foreach (ref Color c; _pm.data)
					c = Color(0, 0, 0, 255);

				long y = 0;
				foreach (Line* l; textBuffer.lines) {
					if (auto _ = l.data.peek!TextLine)
						ft.render(_pm, _.text, 0, y + l.height);
					else
						assert(0, "TODO: implement");
					y += l.height;
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
	FreeType ft;
	bool _quit = false;
	size_t _width, _height;
	bool _wantRedraw;

	TextBuffer textBuffer;
}
