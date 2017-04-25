module de.engine;

import de.platform;
import de.config;
import de.pixelmap;

import std.math;

class Engine {
public:
	this() {
		_width = 1920;
		_height = 1080;
		_platform = new CurrentPlatform("DE", _width, _height);

		_pm.data = new Color[_width * _height];
		_pm.width = _width;
		_pm.height = _height;

		foreach (size_t idx, ref Color c; _pm.data)
			c = Color(cast(ubyte)(idx * idx + idx), cast(ubyte)(idx + idx + idx - idx / 2), cast(ubyte)(idx * (idx + idx) + idx), 255);

	}

	~this() {
		_platform.destroy;
	}

	int run() {
		while (!_quit) {
			_platform.update(this);
			_platform.display(_pm);
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

		foreach (size_t idx, ref Color c; _pm.data)
			c = Color(cast(ubyte)(idx * idx + idx), cast(ubyte)(idx + idx + idx - idx / 2), cast(ubyte)(idx * (idx + idx) + idx), 255);
	}

private:
	IPlatform _platform;
	PixelMap _pm;
	bool _quit = false;
	int _width, _height;
}
