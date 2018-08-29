module app;

version (unittest) {
} else {
	void main(string[] args) {
		import de.terminal : Terminal;
		import de.editor : Editor;

		Terminal.init();
		scope (exit)
			Terminal.destroy;
		Editor editor;
		scope (exit)
			editor.destroy;

		editor.open(args.length > 1 ? args[1] : "testfile.txt");

		while (true) {
			editor.refreshScreen();
			if (!editor.processKeypress())
				break;
		}
	}
}
