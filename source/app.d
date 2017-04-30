import std.stdio;

import de.engine;

int main(string[] args) {
	Engine engine = new Engine();
	scope (exit)
		engine.destroy;

	if (args.length > 1)
		engine.loadFile(args[1]);

	return engine.run();
}
