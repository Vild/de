module de.platform;

import de.engine;
import de.pixelmap;

interface IPlatform {
	void update(Engine engine);
	void display(PixelMap pm);

	@property string title();
	@property string title(string newTitle);

	@property bool wantRedisplay();
}
