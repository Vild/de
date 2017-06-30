module de.container;

struct Color {
align(1):
	ubyte r, g, b, a;

	Color opBinary(string op : "*")(ubyte other) {
		return opBinary!op(other / 255.0f);
	}

	Color opBinary(string op : "*")(float val) {
		return Color(cast(ubyte)(r * val), cast(ubyte)(g * val), cast(ubyte)(b * val), cast(ubyte)(a * val));
	}

	Color opBinary(string op : "+")(Color other) {
		return Color(cast(ubyte)(r + other.r), cast(ubyte)(g + other.g), cast(ubyte)(g + other.g), cast(ubyte)(a + other.a));
	}
}

//TODO: http://stsievert.com/blog/2015/04/23/image-sqrt/
Color mix(Color a, Color b, ubyte amount) {
	return mix(a, b, amount / 255.0f);
}

Color mix(Color a, Color b, float amount) {
	import std.math : sqrt, pow;

	ubyte r_ = cast(ubyte)sqrt(a.r.pow(2) * (1 - amount) + b.r.pow(2) * amount);
	ubyte g_ = cast(ubyte)sqrt(a.g.pow(2) * (1 - amount) + b.g.pow(2) * amount);
	ubyte b_ = cast(ubyte)sqrt(a.b.pow(2) * (1 - amount) + b.b.pow(2) * amount);

	return Color(r_, g_, b_, 255);
}

struct Vec2(T) {
	T x, y;
}

struct Vec3(T) {
	T x, y, z;
}
