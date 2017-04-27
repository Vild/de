module de.pixelmap;

struct Color {
	ubyte r, g, b, a;

	Color opBinary(string op : "*")(ubyte other) {
		return Color(r * other / 255, g * other / 255, b * other / 255, a);
	}
}

struct PixelMap {
	int width, height;
	Color[] data;
}
