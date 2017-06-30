module de.pixelmap;

import de.container;

class PixelMap {
	ulong width, height;
	Color[] data;

	Vec2!ulong getSize() {
		return Vec2!ulong(width, height);
	}
}
