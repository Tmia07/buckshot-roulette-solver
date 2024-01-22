import std.algorithm.searching;
import std.algorithm.sorting;
import std.file;
import std.parallelism;
import std.range;
import std.typecons;

import ae.sys.data;
import ae.sys.datamm;
import ae.sys.file;
import ae.utils.array;
import ae.utils.math.combinatorics;
import ae.utils.math.mixed_radix;
import ae.utils.meta;

import game;

// ------------------------- Items

private struct WithMax(T, T max_)
{
	this(PrePackedGameField value) in(value >= 0 && value <= max_) { this.value = cast(T)value; }
	T value;
	alias value this;
	enum T max = max_;
}

alias PackedShellCount = WithMax!(ubyte, 4);

alias PackedItem = ubyte;
enum packedItemCard = 1 + enumLength!Item; // add 1 for "empty"
alias PackedItemsBase = ushort;
static immutable itemBinomials = BinomialCoefficientTable!(PackedItemsBase, packedItemCard + maxItems, maxItems).generate();
alias ItemCNS = CNS!(PackedItemsBase, PackedItem, maxItems, packedItemCard, /*lexicographic:*/false, /*multiset:*/true, itemBinomials);
enum packedItemsCard = 1287; // == multisetCoefficient(packedItemCard, maxItems) == ItemCNS.packedCard
alias PackedItems = WithMax!(PackedItemsBase, packedItemsCard - 1);

alias PackedHealth = WithMax!(ubyte, 3); // min == 1 !

enum PackedHandcuffState : ubyte { none, playerWillSkip, playerWillBreak, dealerWillSkip, dealerWillBreak }
immutable HandcuffState[2][enumLength!PackedHandcuffState] packedHandcuffStates = [
	[HandcuffState.none, HandcuffState.none],
	[HandcuffState.willSkip, HandcuffState.none],
	[HandcuffState.willBreak, HandcuffState.none],
	[HandcuffState.none, HandcuffState.willSkip],
	[HandcuffState.none, HandcuffState.willBreak],
];

enum PackedNextShell : ubyte { unknown, blank, live }
immutable Nullable!ShellType[enumLength!PackedNextShell] packedNextShell = [
	Nullable!ShellType.init,
	ShellType.blank.nullable,
	ShellType.live.nullable,
];

struct PrePackedGame
{
	Character currentTurn;
	PackedShellCount[enumLength!ShellType] shells;

	// (we could save 226491/1679616 (~13%) if we make >2 cigarette packs unrepresentable...)
	PackedItems[enumLength!Character] items;
	PackedHealth[enumLength!Character] health;
	PackedHandcuffState handcuffs;
	PackedNextShell nextShell;
	bool shotgunSawedOff;

	static PackedItems packItems(byte[enumLength!Item] items) nothrow @nogc
	{
		PackedItem[maxItems] packedItems;
		size_t i = maxItems;
		foreach_reverse (Item itemType; Item.init .. enumLength!Item)
			foreach (j; 0 .. items[itemType])
				packedItems[--i] = cast(ubyte)(1 + itemType);
		packedItems[0 .. i] = 0;
		PackedItems result = ItemCNS.pack(packedItems);
		return result;
	}

	static byte[enumLength!Item] unpackItems(PackedItems p) nothrow @nogc
	in (p < packedItemsCard)
	{
		PackedItem[maxItems] packedItems = ItemCNS.unpack(p);
		byte[enumLength!Item] result;
		foreach (packedItem; packedItems)
			if (packedItem > 0)
				result[cast(Item)(packedItem - 1)]++;
		return result;
	}

	this(Game game) nothrow @nogc
	{
		this.currentTurn = game.currentTurn;
		foreach (i, value; game.shells) this.shells[i] = value;
		foreach (i, value; game.items) this.items[i] = packItems(value);
		foreach (i, value; game.health) this.health[i] = cast(ubyte)(value - 1);
		this.handcuffs = cast(PackedHandcuffState)packedHandcuffStates.indexOf(game.handcuffs);
		this.nextShell = cast(PackedNextShell)packedNextShell.indexOf(game.nextShell);
		this.shotgunSawedOff = game.shotgunSawedOff;
	}

	Game unpack() nothrow @nogc
	{
		Game game;
		game.currentTurn = this.currentTurn;
		foreach (i, value; this.shells) game.shells[i] = value;
		foreach (i, value; this.items) game.items[i] = unpackItems(value);
		foreach (i, value; this.health) game.health[i] = cast(ubyte)(value + 1);
		game.handcuffs = packedHandcuffStates[this.handcuffs];
		game.nextShell = packedNextShell[this.nextShell];
		game.shotgunSawedOff = this.shotgunSawedOff;
		return game;
	}
}

alias PrePackedGameField = ushort; // biggest pre-packed game field
alias PackedGame = ulong;

alias GameSerializer = SerializationCoder!(MixedRadixCoder!(PrePackedGameField, PackedGame), PrePackedGame);

static assert(GameSerializer.minValue == 0);
immutable PackedGame packedGameCard = GameSerializer.cardinality;

PackedGame packGame(Game game) nothrow @nogc { return GameSerializer.serialize(PrePackedGame(game)); }
Game unpackGame(PackedGame packed) nothrow @nogc { return GameSerializer.deserialize(packed).unpack(); }


version (main_packing)
void main()
{
	import std.stdio: stderr;

	// foreach (i; 0 .. packedGameCard)
	// {
	// 	if (i % 100_000 == 0) stderr.writeln(i, " / ", packedGameCard);
	// 	assert(i.unpackGame().packGame() == i);
	// }

	// while (true)
	// {
	// 	import std.random : uniform;
	// 	auto i = uniform(0, packedGameCard);
	// 	if (i % 100_000 == 0) stderr.writeln(i, " / ", packedGameCard);
	// 	assert(i.unpackGame().packGame() == i);
	// }
}
