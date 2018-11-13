module de.styler;

import de.line;
import de.utfstring;
import de.build;

private enum errorToken = 0;

struct Styler {
public static:
	Line.Part[] styleTextIntoParts(UTFString str) {

		Line.Part[] output;
		if (!str.length) {
			output ~= Line.Part(TextStyle(), str);
			return output;
		}

		/*p.style = Config.basicTypeStyle;
p.style = Config.numbericStyle;
p.style = Config.operatorStyle;
p.style = Config.keywordStyle;
p.style = Config.stringLiteralStyle;
p.style = Config.protectionStyle;
p.style = Config.specialTokenStyle;
p.style = Config.literalStyle;*/

		TextStyle[] styles = [
			TextStyle(), Config.basicTypeStyle, Config.numbericStyle, Config.operatorStyle, Config.keywordStyle,
			Config.stringLiteralStyle, Config.protectionStyle, Config.specialTokenStyle, Config.literalStyle
		];

		ptrdiff_t startIdx;
		size_t styleIdx;
		bool continueLoop = true;
		while (continueLoop) {
			import std.string : indexOfAny;

			ptrdiff_t idx = str.rawData.indexOfAny(" ()'\",.;\t!`{}[]*+-/\\", startIdx);
			if (startIdx == idx)
				idx++;

			if (idx == -1) {
				continueLoop = false;
				idx = str.rawData.length;
			}
			Line.Part p;
			p.str = UTFString(str.rawData[startIdx .. idx]);

			startIdx = idx;
			p.style = styles[styleIdx];
			if (p.str.length) {
				output ~= p;
				styleIdx = (styleIdx + 1) % styles.length;
			}
		}
		return output;
	}
}

pragma(lib, "libSDL2.so");

private extern extern (C) void SDL_ShowSimpleMessageBox(uint flags, const(char)* title, const(char)* message, void* null_);
void msgbox(string msg) {
	import std.string : toStringz;

	SDL_ShowSimpleMessageBox(0, "DE", msg.toStringz, null);
}
