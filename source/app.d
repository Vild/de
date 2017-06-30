import std.stdio;

import de.engine;

int main(string[] args) {
	Engine engine = new Engine();
	scope (exit)
		engine.destroy;

	engine.loadFile((args.length > 1) ? args[1] : "Planning.org");

	return engine.run();
}
