module de.config;

string FONT = "Dejavu Sans Mono";

public:
version (linux) {
	import de.platform.sdl : SDLPlatform;

	alias CurrentPlatform = SDLPlatform;
}
