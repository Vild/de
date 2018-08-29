module de.build;

static struct Build {
static:
	enum string version_ = "0.0.1";
}

static struct Config {
static:
	size_t tabSize = 2;

	wchar tabCharStart = '↦';
	wchar tabCharStartUnaligned = '↦';
	wchar tabMiddle = ' ';
	wchar tabEnd = ' ';

	wchar spaceChar = '⬩';
}
