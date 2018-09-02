module de.build;

import de.line : TextStyle;
import de.terminal : Color;

static struct Build {
static:
	enum string version_ = "0.0.1";
}

static struct Config {
static:
	size_t tabSize = 2;

	dchar tabCharStart = '↦';
	dchar tabCharStartUnaligned = '↦';
	dchar tabMiddle = ' ';
	dchar tabEnd = ' ';

	dchar spaceChar = '⬩';

	TextStyle lineNumberStyle = {bright: true};
	TextStyle lineNumberSeparatorStyle = {dim: true};
	dchar lineNumberSeparator = '│';
}
