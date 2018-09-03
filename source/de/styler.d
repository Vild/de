module de.styler;

import dparse.lexer;

import de.line;
import de.utfstring;
import de.build;

shared static this() {
	Styler.sc = StringCache(StringCache.defaultBucketCount);
}

struct Styler {
public static:
	Line.Part[] styleTextIntoParts(UTFString str) {
		Line.Part[] output;
		if (!str.length) {
			output ~= Line.Part(TextStyle(), str);
			return output;
		}
		foreach (tok; str.rawData.byToken(lc, &sc)) {
			Line.Part p;
			p.str = tok.text.length ? UTFString(tok.text) : UTFString(.str(tok.type));
			if (tok.type.isBasicType) {
				p.style = Config.basicTypeStyle;
			} else if (tok.type.isNumberLiteral) {
				p.style = Config.numbericStyle;
			} else if (tok.type.isOperator) {
				p.style = Config.operatorStyle;
			} else if (tok.type.isKeyword) {
				p.style = Config.keywordStyle;
			} else if (tok.type.isStringLiteral) {
				p.style = Config.stringLiteralStyle;
			} else if (tok.type.isProtection) {
				p.style = Config.protectionStyle;
			} else if (tok.type.isSpecialToken) {
				p.style = Config.specialTokenStyle;
			} else if (tok.type.isLiteral) {
				p.style = Config.literalStyle;
			}
			output ~= p;
		}
		return output;
	}

	LexerConfig lc = {stringBehavior:
	StringBehavior.source, whitespaceBehavior : WhitespaceBehavior.include};
	StringCache sc = void;
}
