module extractCharWidths;

import std.net.curl;
import std.algorithm;
import std.regex;
import std.conv;
import std.exception;
import std.meta;
import std.uni;
import std.range;
import std.stdio;

enum Width {
	A = 1 << 0,
	F = 1 << 1,
	H = 1 << 2,
	Na = 1 << 3,
	N = 1 << 4,
	W = 1 << 5
}

alias CharRange = AliasSeq!(uint /* start */ , uint /* end */ );
alias CharRangeMatch = AliasSeq!(CharRange, Width);

void main() {
	import std.file : write, exists;

	auto regex = ctRegex!`^(\w{4})(?:\.\.(\w{4}))?;(A|F|H|Na|N|W)`;

	string spin = "|/-\\";
	size_t count;
	byte[dchar] widthMap;

	if (!exists("EastAsianWidth.txt"))
		download("http://ftp.unicode.org/Public/UNIDATA/EastAsianWidth.txt", "EastAsianWidth.txt");

	File data = File("EastAsianWidth.txt", "r");

	// dfmt off
	data
		.byLine
		.filter!(l => l.length && l[0] != '#')
		.map!(l => l.matchFirst(regex))
		.filter!(c => !c.empty)
		.filter!(c => c[3].to!Width & (Width.F | Width.W))
		.each!((ref range) => {
				uint from = range[1].to!uint(16);
				uint to = range[2].to!uint(16).ifThrown(from);

				foreach (c; from .. to + 1)
					widthMap[c] = 2;
			}
		);
	// dfmt on

	// dfmt off
	foreach (ch; (
			unicode.Grapheme_extend |
			unicode.hangulSyllableType("V") |
			unicode.hangulSyllableType("T") | unicode.Default_Ignorable_Code_Point
		).byCodepoint) {
		widthMap[ch] = 0;
	}
	// dfmt on

	File output = File("views/getCharDisplayWidth.d", "w");
	output.write(q{
struct TrieEntry(T...) {
	size_t[] offsets;
	size_t[] sizes;
	size_t[] data;
}

template getCharDisplayWidth() {
	private template widthMap() {
		auto loadEntries() {
			import std.uni : CodepointTrie;

			auto asTrie(T...)(in TrieEntry!T e) {
				return const(CodepointTrie!T)(e.offsets, e.sizes, e.data);
			}
			return asTrie(displayWidthTrieEntries);
		}

		private alias Impl = typeof(loadEntries());
		private immutable(Impl) widthMap;

		static this() {
			widthMap = loadEntries();
		}
	}

	alias impl = widthMap!();
	int getCharDisplayWidth(dchar ch) {
		return ((ch & 0x80) == 0 && ch < 0xAD) ? 1 : impl[ch];
	}
}
	});

	writeBest3Level(output, "displayWidth", widthMap, 1);
}

// From https://github.com/quickfur/strwidth/blob/master/compileWidth.d#L205
// License: Unknown but probably Boost
alias List_1 = AliasSeq!(4, 5, 6, 7, 8);

void writeBest3Level(V, K)(File sink, string name, V[K] map, V defValue = V.init) {
	void delegate(File) write;
	alias List = AliasSeq!(4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
	size_t min = size_t.max;
	auto range = zip(map.values, map.keys).array;
	foreach (lvl_1; List_1) //to have the first stage index fit in byte
		foreach (lvl_2; List) {
			static if (lvl_1 + lvl_2 <= 16) // into ushort
			{
					enum lvl_3 = 21 - lvl_2 - lvl_1;
					auto t = codepointTrie!(V, lvl_1, lvl_2, lvl_3)(range, defValue);
					if (t.bytes < min) {
						min = t.bytes;
						write = createPrinter!(lvl_1, lvl_2, lvl_3)(name, t);
					}
				}
		}
	write(sink);
}

template createPrinter(Params...) {
	import std.traits : Unqual;

	void delegate(File) createPrinter(T)(string name, T trie) {
		return (File sink) {
			sink.writef("//%d bytes\nenum %sTrieEntries = TrieEntry!(%s", trie.bytes, name, Unqual!(typeof(T.init[0])).stringof);
			foreach (lvl; Params[0 .. $])
				sink.writef(", %d", lvl);
			sink.write(")(");
			trie.store(sink.lockingTextWriter());
			sink.writeln(");");
		};
	}
}
