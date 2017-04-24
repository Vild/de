module de.config;

public:
version (linux) {
	import de.platform.sdl : SDLPlatform;

	alias CurrentPlatform = SDLPlatform;
}
