module de.config;

string FONT = "DejavuSansMono";

public:
version (linux) {
	import de.platform.sdl : SDLPlatform;

	alias CurrentPlatform = SDLPlatform;
}
