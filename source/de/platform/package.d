module de.platform;

import de.engine;
import de.pixelmap;

interface IPlatform {
	void update(Engine engine);
	void display(PixelMap pm);
	//TODO: Add push texture layer?
	//TODO: Separate render function
	//TODO: Check if needed redraw

	@property string title();
	@property string title(string newTitle);
}
