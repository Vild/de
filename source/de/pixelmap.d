module de.pixelmap;

struct Color {
	ubyte r, g, b, a;
}

struct PixelMap {
	int width, height;
	Color[] data;
}
