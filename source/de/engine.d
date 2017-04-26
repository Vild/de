module de.engine;

import de.platform;
import de.config;
import de.pixelmap;

import std.math;
import core.thread;
import std.datetime;

class Engine {
public:
	this() {
		_width = 1280;
		_height = 720;
		_platform = new CurrentPlatform("DE", _width, _height);

		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;

		foreach (ref Color c; _pm.data)
			c = Color(0, 0, 0, 255);
	}

	~this() {
		_platform.destroy;
	}

	int run() {
		_wantRedraw = true;
		while (!_quit) {
			_platform.update(this);
			if (_wantRedraw || _platform.wantRedisplay) {
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

	void resize(int width, int height) {
		_width = width;
		_height = height;

		_pm.data.destroy;
		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;

		foreach (ref Color c; _pm.data)
			c = Color(0, 0, 0, 255);
	}

private:
	IPlatform _platform;
	PixelMap _pm;
	bool _quit = false;
	int _width, _height;
	bool _wantRedraw;
}
