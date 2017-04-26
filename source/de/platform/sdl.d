module de.platform.sdl;

import derelict.sdl2.sdl;
import std.string : toStringz;

import de.platform;
import de.engine;
import de.pixelmap;

shared static this() {
	DerelictSDL2.load();
	SDL_Init(SDL_INIT_EVENTS | SDL_INIT_VIDEO);
}

shared static ~this() {
	SDL_Quit();
}

class SDLPlatform : IPlatform {
public:
	this(string title, int width, int height) {
		_title = title;
		_width = width;
		_height = height;
		_window = SDL_CreateWindow(title.toStringz, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, width, height,
				SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN);
		assert(_window, "Failed to create window");
		_renderer = SDL_CreateRenderer(_window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
		assert(_renderer, "Failed to create renderer");
		_texture = SDL_CreateTexture(_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, width, height);
		assert(_texture, "Failed to create texture");
	}

	~this() {
		SDL_DestroyRenderer(_renderer);
		SDL_DestroyWindow(_window);
	}

	void update(Engine engine) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
			switch (event.type) {
			case SDL_QUIT:
				engine.quit();
				break;

			case SDL_WINDOWEVENT:
				switch (event.window.event) {
				case SDL_WINDOWEVENT_CLOSE:
					engine.quit();
					break;

				case SDL_WINDOWEVENT_SIZE_CHANGED:
					_width = event.window.data1;
					_height = event.window.data2;
					_resizeTexture();
					engine.resize(_width, _height);
					_wantRedisplay = true;
					break;

				case SDL_WINDOWEVENT_SHOWN:
				case SDL_WINDOWEVENT_EXPOSED:
					_wantRedisplay = true;
					break;

				default:
					break;
				}
				break;

			case SDL_KEYDOWN:
				if (event.key.keysym.sym == SDLK_ESCAPE)
					engine.quit();
				break;

			default:
				break;
			}
		}
	}

	void display(PixelMap pm) {
		_wantRedisplay = false;
		Color* pixels;
		int pitch;

		SDL_LockTexture(_texture, null, cast(void**)&pixels, &pitch);
		pixels[0 .. _width * _height] = pm.data[0 .. pm.width * pm.height];
		SDL_UnlockTexture(_texture);

		SDL_RenderClear(_renderer);
		SDL_RenderCopy(_renderer, _texture, null, null);
		SDL_RenderPresent(_renderer);
	}

	@property string title() {
		return _title;
	}

	@property string title(string newTitle) {
		_title = newTitle;
		SDL_SetWindowTitle(_window, _title.toStringz);
		return _title;
	}

	@property bool wantRedisplay() {
		return _wantRedisplay;
	}

private:
	SDL_Window* _window;
	SDL_Renderer* _renderer;
	SDL_Texture* _texture;

	string _title;
	int _width, _height;
	bool _wantRedisplay;

	void _resizeTexture() {
		SDL_DestroyTexture(_texture);
		_texture = SDL_CreateTexture(_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, _width, _height);
		assert(_texture, "Failed to create texture");
	}
}
