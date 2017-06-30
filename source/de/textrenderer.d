module de.textrenderer;

import derelict.freetype.ft;
import fontconfig.fontconfig;

import std.string;
import std.conv;

import de.pixelmap;
import de.textbuffer;
import de.container;

shared static this() {
	DerelictFT.load();
}

class FreeType {
public:
	this(string fontName) {
		import std.stdio : writefln;
		import std.process : execute;
		import std.file : dirEntries, SpanMode, exists;
		import std.path : expandTilde, baseName;

		FT_Init_FreeType(&_library).enforceFT;

		assert(FcInit());
		const compareFamily = fontName.strip.toLower;

		string fontPath;

		writefln("Searching for font '%s'...", fontName);

		FcPattern* pat = FcPatternCreate();
		FcObjectSet* os = FcObjectSetBuild(FC_FAMILY.ptr, FC_STYLE.ptr, FC_LANG.ptr, FC_FILE.ptr, null);
		FcFontSet* fs = FcFontList(null, pat, os);
		assert(fs);
		foreach (FcPattern* font; fs.fonts[0 .. fs.nfont]) {
			char* file, style, family;
			if (FcPatternGetString(font, FC_FILE, 0, &file) != FcResult.FcResultMatch || FcPatternGetString(font, FC_FAMILY,
					0, &family) != FcResult.FcResultMatch || FcPatternGetString(font, FC_STYLE, 0, &style) != FcResult.FcResultMatch)
				continue;

			auto dFamily = family.fromStringz;
			if (dFamily.strip.toLower != compareFamily)
				continue;
			auto dFile = file.fromStringz;
			auto dStyle = style.fromStringz;

			writefln("\tFound: %s (style %s)", dFile, dStyle);
			//TODO: Support bold and stuff
			if (dStyle == "Regular" || dStyle == "Book")
				fontPath = (cast(string)dFile).dup;
		}
		FcFontSetDestroy(fs);

		assert(fontPath.length);

		FT_New_Face(_library, fontPath.toStringz, 0, &_face).enforceFT;
	}

	~this() {
		FT_Done_Face(_face);

		FcFini();

		FT_Done_Library(_library);
	}

	Vec2!ulong getSize(dstring str, TextStyle style, size_t fontSize) {
		import std.algorithm : max, min;

		ulong w, h;
		FT_Set_Char_Size(_face, 0, cast(uint)fontSize * 64 + 32, 0, 0).enforceFT;
		foreach (ch; str) {
			FT_Glyph glyph;
			auto glyph_index = FT_Get_Char_Index(_face, ch);

			int FT_LOAD_BITMAP_METRICS_ONLY = 1 << 22;
			FT_Load_Glyph(_face, glyph_index, FT_LOAD_DEFAULT | FT_LOAD_COMPUTE_METRICS | FT_LOAD_BITMAP_METRICS_ONLY).enforceFT;
			FT_Get_Glyph(_face.glyph, &glyph);

			w += _face.glyph.advance.x >> 6;
			h = h.max(_face.glyph.metrics.height >> 6);
		}
		return Vec2!ulong(w, cast(ulong)(h * 1.5));
	}

	void render(ref PixelMap pm, ref TextPart text, long x, long y) {
		FT_Set_Char_Size(_face, 0, cast(uint)text.fontSize * 64 + 32, 0, 0).enforceFT;
		foreach (ch; text.text)
			render(pm, ch, text.style, text.fontSize, x, y, text.fg);
	}

	void render(ref PixelMap pm, dchar ch, TextStyle style, size_t fontSize, ref long x, ref long y, Color fg) {
		auto glyph_index = FT_Get_Char_Index(_face, ch);

		FT_Load_Glyph(_face, glyph_index, FT_LOAD_DEFAULT).enforceFT;
		FT_Render_Glyph(_face.glyph, FT_RENDER_MODE_NORMAL).enforceFT;

		_draw(pm, _face.glyph.bitmap, x + _face.glyph.bitmap_left, y - _face.glyph.bitmap_top, fg);

		x += _face.glyph.advance.x >> 6;
		y += _face.glyph.advance.y >> 6;
	}

private:
	FT_Library _library;
	FT_Face _face;

	void _draw(ref PixelMap image, const ref FT_Bitmap bitmap, long x, long y, Color fg) {
		if (bitmap.pitch <= 0)
			return;
		long w = bitmap.width;
		long h = bitmap.rows;
		if (x + w < 0 || y + h < 0 || x >= image.width || y >= image.height)
			return;

		if (x < 0) {
			w -= x;
			x = 0;
		}
		if (w <= 0 || h <= 0)
			return;
		if (x + w >= image.width)
			w = image.width - x - 1;

		if (bitmap.pixel_mode == FT_PIXEL_MODE_GRAY) {
			for (size_t ly; ly < h; ly++) {
				if (ly + y < 0 || ly + y >= image.height)
					continue;
				for (size_t lx; lx < w; lx++)
					image.data[lx + x + (ly + y) * image.width] = mix(image.data[lx + x + (ly + y) * image.width], fg,
							bitmap.buffer[lx + ly * bitmap.pitch] / (bitmap.num_grays * 1.0f));
			}
		} else if (bitmap.pixel_mode == FT_PIXEL_MODE_MONO) {
			for (size_t ly; ly < h; ly++) {
				if (ly + y < 0 || ly + y >= image.height)
					continue;
				for (size_t lx; lx < w; lx++)
					if (bitmap.buffer[(lx / 8) + ly * bitmap.pitch] & (1 << (7 - (lx % 8))))
						image.data[lx + x + (ly + y) * image.width] = fg;
			}
		} else {
			throw new Exception("Unsupported bitmap format: " ~ to!string(cast(FTPixelMode)bitmap.pixel_mode));
		}
	}
}

enum FTErrors {
	FT_Err_Ok = 0x00,
	FT_Err_Cannot_Open_Resource = 0x01,
	FT_Err_Unknown_File_Format = 0x02,
	FT_Err_Invalid_File_Format = 0x03,
	FT_Err_Invalid_Version = 0x04,
	FT_Err_Lower_Module_Version = 0x05,
	FT_Err_Invalid_Argument = 0x06,
	FT_Err_Unimplemented_Feature = 0x07,
	FT_Err_Invalid_Table = 0x08,
	FT_Err_Invalid_Offset = 0x09,
	FT_Err_Array_Too_Large = 0x0A,
	FT_Err_Missing_Module = 0x0B,
	FT_Err_Missing_Property = 0x0C,

	FT_Err_Invalid_Glyph_Index = 0x10,
	FT_Err_Invalid_Character_Code = 0x11,
	FT_Err_Invalid_Glyph_Format = 0x12,
	FT_Err_Cannot_Render_Glyph = 0x13,
	FT_Err_Invalid_Outline = 0x14,
	FT_Err_Invalid_Composite = 0x15,
	FT_Err_Too_Many_Hsize_ts = 0x16,
	FT_Err_Invalid_Pixel_Size = 0x17,

	FT_Err_Invalid_Handle = 0x20,
	FT_Err_Invalid_Library_Handle = 0x21,
	FT_Err_Invalid_Driver_Handle = 0x22,
	FT_Err_Invalid_Face_Handle = 0x23,
	FT_Err_Invalid_Size_Handle = 0x24,
	FT_Err_Invalid_Slot_Handle = 0x25,
	FT_Err_Invalid_CharMap_Handle = 0x26,
	FT_Err_Invalid_Cache_Handle = 0x27,
	FT_Err_Invalid_Stream_Handle = 0x28,

	FT_Err_Too_Many_Drivers = 0x30,
	FT_Err_Too_Many_Extensions = 0x31,

	FT_Err_Out_Of_Memory = 0x40,
	FT_Err_Unlisted_Object = 0x41,

	FT_Err_Cannot_Open_Stream = 0x51,
	FT_Err_Invalid_Stream_Seek = 0x52,
	FT_Err_Invalid_Stream_Skip = 0x53,
	FT_Err_Invalid_Stream_Read = 0x54,
	FT_Err_Invalid_Stream_Operation = 0x55,
	FT_Err_Invalid_Frame_Operation = 0x56,
	FT_Err_Nested_Frame_Access = 0x57,
	FT_Err_Invalid_Frame_Read = 0x58,

	FT_Err_Raster_Uninitialized = 0x60,
	FT_Err_Raster_Corrupted = 0x61,
	FT_Err_Raster_Overflow = 0x62,
	FT_Err_Raster_Negative_Height = 0x63,

	FT_Err_Too_Many_Caches = 0x70,

	FT_Err_Invalid_Opcode = 0x80,
	FT_Err_Too_Few_Arguments = 0x81,
	FT_Err_Stack_Overflow = 0x82,
	FT_Err_Code_Overflow = 0x83,
	FT_Err_Bad_Argument = 0x84,
	FT_Err_Divide_By_Zero = 0x85,
	FT_Err_Invalid_Reference = 0x86,
	FT_Err_Debug_OpCode = 0x87,
	FT_Err_ENDF_In_Exec_Stream = 0x88,
	FT_Err_Nested_DEFS = 0x89,
	FT_Err_Invalid_CodeRange = 0x8A,
	FT_Err_Execution_Too_Long = 0x8B,
	FT_Err_Too_Many_Function_Defs = 0x8C,
	FT_Err_Too_Many_Instruction_Defs = 0x8D,
	FT_Err_Table_Missing = 0x8E,
	FT_Err_Horiz_Header_Missing = 0x8F,
	FT_Err_Locations_Missing = 0x90,
	FT_Err_Name_Table_Missing = 0x91,
	FT_Err_CMap_Table_Missing = 0x92,
	FT_Err_Hmtx_Table_Missing = 0x93,
	FT_Err_Post_Table_Missing = 0x94,
	FT_Err_Invalid_Horiz_Metrics = 0x95,
	FT_Err_Invalid_CharMap_Format = 0x96,
	FT_Err_Invalid_PPem = 0x97,
	FT_Err_Invalid_Vert_Metrics = 0x98,
	FT_Err_Could_Not_Find_Context = 0x99,
	FT_Err_Invalid_Post_Table_Format = 0x9A,
	FT_Err_Invalid_Post_Table = 0x9B,

	FT_Err_Syntax_Error = 0xA0,
	FT_Err_Stack_Underflow = 0xA1,
	FT_Err_Ignore = 0xA2,
	FT_Err_No_Unicode_Glyph_Name = 0xA3,
	FT_Err_Glyph_Too_Big = 0xA4,

	FT_Err_Missing_Startfont_Field = 0xB0,
	FT_Err_Missing_Font_Field = 0xB1,
	FT_Err_Missing_Size_Field = 0xB2,
	FT_Err_Missing_Fontboundingbox_Field = 0xB3,
	FT_Err_Missing_Chars_Field = 0xB4,
	FT_Err_Missing_Startchar_Field = 0xB5,
	FT_Err_Missing_Encoding_Field = 0xB6,
	FT_Err_Missing_Bbx_Field = 0xB7,
	FT_Err_Bbx_Too_Big = 0xB8,
	FT_Err_Corrupted_Font_Header = 0xB9,
	FT_Err_Corrupted_Font_Glyphs = 0xBA,

	FT_Err_Max,
}

enum FTPixelMode {
	FT_PIXEL_MODE_NONE = 0,
	FT_PIXEL_MODE_MONO,
	FT_PIXEL_MODE_GRAY,
	FT_PIXEL_MODE_GRAY2,
	FT_PIXEL_MODE_GRAY4,
	FT_PIXEL_MODE_LCD,
	FT_PIXEL_MODE_LCD_V,
	FT_PIXEL_MODE_MAX
}

void enforceFT(FT_Error err_) {
	import std.conv : to;

	auto err = cast(FTErrors)err_;
	if (err == FT_Err_Ok)
		return;
	throw new Exception(err.to!string);
}
