module de.text;

import derelict.freetype.ft;

shared static this() {
	DerelictFT.load();
}

class FreeType {
public:
	this(string font) {
		assert(FT_Init_FreeType(&_library) == FT_Err_Ok);
		assert(FT_New_Face(library, font, 0, &_face) == FT_Err_Ok);
		//TODO: https://freetype.org/freetype2/docs/tutorial/step1.html#section-5
	}

private:
	FT_Library _library;
	FT_Face _face;
}
