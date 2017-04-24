module de.engine;

import de.platform;
import de.config;

class Engine {
public:
	this() {
		platform = new CurrentPlatform();
	}

	~this() {
		platform.destroy;
	}

private:
	IPlatform platform;
}
