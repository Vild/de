module de.platform.sdl;

import derelict.sdl2.sdl;

import de.platform;

shared static this() {
	DerelictSDL2.load();
}

class SDLPlatform : IPlatform {

}
