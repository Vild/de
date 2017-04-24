import std.stdio;

import de.engine;

int main(string[] args) {
	Engine engine = new Engine();
	scope (exit)
		engine.destroy;
	return 0;
}
